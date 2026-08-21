defmodule Kinda.Sandbox.Backend.LocalProcess.Command do
  @moduledoc false

  @behaviour Kinda.Sandbox.Capability.Command

  alias Kinda.Sandbox.Backend.LocalProcess
  alias Kinda.Sandbox.Backend.LocalProcess.State
  alias Kinda.Sandbox.Command.Spec
  alias Kinda.Sandbox.Error
  alias Kinda.Sandbox.Native

  @impl true
  def stream(%State{} = state, %Spec{} = spec) do
    if absolute_missing?(spec.executable) do
      {:error,
       Error.exception(
         reason: :backend_failure,
         backend: LocalProcess,
         operation: :command,
         message: "command executable does not exist",
         details: %{executable: spec.executable}
       )}
    else
      build_native_stream(state, spec)
    end
  end

  @impl true
  def terminate(process, _reason, grace_milliseconds) do
    Native.terminate(process, grace_milliseconds)
  end

  defp build_native_stream(state, spec) do
    executable = System.find_executable(spec.executable) || spec.executable
    cwd = Path.join(state.directory, spec.cwd)
    environment = native_environment(state.env, spec)
    stdin = input(spec.stdin)

    case Native.spawn(executable, spec.args, cwd, environment, stdin) do
      {:ok, process} ->
        metadata = %{
          streams: :separate,
          process_tree_termination?: true,
          cwd: spec.cwd,
          executable: executable
        }

        {:ok, Stream.concat([{:metadata, metadata}], native_stream(process)), process}

      {:error, reason} ->
        {:error, backend_failure("could not spawn command", reason, spec.executable)}
    end
  end

  defp absolute_missing?(executable) do
    Path.type(executable) == :absolute and not File.regular?(executable)
  end

  defp native_stream(process) do
    Stream.resource(
      fn -> process end,
      fn process -> native_event(process) end,
      fn _process -> :ok end
    )
  end

  defp native_environment(sandbox_env, spec) do
    sandbox_env
    |> environment_map(spec)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
  end

  defp environment_map(sandbox_env, spec) do
    ambient = normalize_environment(System.get_env())

    inherited =
      spec.inherit_env
      |> Enum.map(&normalize_environment_key/1)
      |> Map.new(fn key -> {key, Map.get(ambient, key)} end)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    normalize_environment(sandbox_env)
    |> Map.merge(inherited)
    |> Map.merge(normalize_environment(spec.env))
  end

  defp normalize_environment(environment) do
    Map.new(environment, fn {key, value} -> {normalize_environment_key(key), value} end)
  end

  defp normalize_environment_key(key) do
    if windows?(), do: String.upcase(key), else: key
  end

  defp input(:closed), do: ""
  defp input(binary), do: binary

  defp native_event(process) do
    case Native.read_event(process) do
      :idle -> native_event(process)
      :done -> {:halt, process}
      {:error, reason} -> raise "native process read failed: #{inspect(reason)}"
      event when is_tuple(event) -> {[event], process}
    end
  end

  defp backend_failure(message, reason, executable) do
    Error.exception(
      reason: :backend_failure,
      backend: LocalProcess,
      operation: :command,
      message: message,
      cause: reason,
      details: %{executable: executable}
    )
  end

  defp windows?, do: match?({:win32, _name}, :os.type())
end
