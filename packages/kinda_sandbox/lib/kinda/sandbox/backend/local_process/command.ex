defmodule Kinda.Sandbox.Backend.LocalProcess.Command do
  @moduledoc false

  @behaviour Kinda.Sandbox.Capability.Command

  alias Kinda.Sandbox.Backend.LocalProcess
  alias Kinda.Sandbox.Backend.LocalProcess.State
  alias Kinda.Sandbox.Command.Spec
  alias Kinda.Sandbox.Error
  alias Kinda.Sandbox.Native

  # ExCmd requires a timeout above its 50 ms bookkeeping window; 51 ms
  # advances directly to its force-kill stage on Windows.
  @legacy_immediate_exit_timeout 51

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
      if windows?(), do: build_legacy_stream(state, spec), else: build_native_stream(state, spec)
    end
  end

  @impl true
  def terminate({:legacy_worker, worker}, _reason, _grace_milliseconds) do
    case linked_command_process(worker) do
      nil -> :ok
      process -> terminate_ex_cmd(process, worker)
    end
  end

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

  defp build_legacy_stream(state, spec) do
    command = [spec.executable | spec.args]
    events = legacy_process_stream(command, state, spec)

    metadata = %{
      streams: :merged,
      process_tree_termination?: false,
      cwd: spec.cwd,
      executable: spec.executable
    }

    {:ok, Stream.concat([{:metadata, metadata}], events), {:legacy_worker, self()}}
  end

  defp legacy_process_stream(command, state, spec) do
    command
    |> ExCmd.stream(ex_cmd_options(state, spec))
    |> Stream.map(fn
      {:exit, {:status, status}} -> {:exit, status}
      {:exit, :epipe} -> {:signal, 0}
      data when is_binary(data) -> {:stdout, data}
    end)
  end

  defp absolute_missing?(executable) do
    Path.type(executable) == :absolute and not File.regular?(executable)
  end

  defp ex_cmd_options(state, spec) do
    [
      cd: Path.join(state.directory, spec.cwd),
      env: legacy_environment(state.env, spec),
      input: input(spec.stdin),
      stderr: :redirect_to_stdout,
      max_chunk_size: 64 * 1024 - 5
    ]
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

  defp legacy_environment(sandbox_env, spec) do
    ambient = normalize_environment(System.get_env())
    scrubbed = Map.new(ambient, fn {key, _value} -> {key, ""} end)

    scrubbed
    |> Map.merge(environment_map(sandbox_env, spec))
    |> Map.to_list()
  end

  defp normalize_environment(environment) do
    Map.new(environment, fn {key, value} -> {normalize_environment_key(key), value} end)
  end

  defp normalize_environment_key(key) do
    if windows?(), do: String.upcase(key), else: key
  end

  defp input(:closed), do: ""
  defp input(binary), do: binary

  defp linked_command_process(worker) do
    case Process.info(worker, :links) do
      {:links, links} ->
        Enum.find(links, &ex_cmd_process?/1)

      nil ->
        nil
    end
  end

  defp ex_cmd_process?(process) do
    case Process.info(process, :dictionary) do
      {:dictionary, dictionary} ->
        match?(
          {:"$initial_call", {ExCmd.Process, :init, 1}},
          List.keyfind(dictionary, :"$initial_call", 0)
        )

      nil ->
        false
    end
  end

  defp terminate_ex_cmd(process, worker) do
    terminate_legacy_process_tree(process)
    monitor = Process.monitor(process)
    GenServer.cast(process, {:prepare_exit, worker, @legacy_immediate_exit_timeout})

    receive do
      {:DOWN, ^monitor, :process, ^process, _reason} -> :ok
    after
      1_500 ->
        Process.demonitor(monitor, [:flush])
        :ok
    end
  end

  defp terminate_legacy_process_tree(process) do
    with {:ok, os_pid} <- ExCmd.Process.os_pid(process),
         taskkill when is_binary(taskkill) <- System.find_executable("taskkill") do
      _ = System.cmd(taskkill, ["/PID", Integer.to_string(os_pid), "/T", "/F"])
    end

    :ok
  end

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
