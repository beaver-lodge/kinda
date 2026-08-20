defmodule Kinda.Sandbox.Backend.LocalNative.Command do
  @moduledoc false

  @behaviour Kinda.Sandbox.Capability.Command

  alias Kinda.Sandbox.Backend.LocalNative.State
  alias Kinda.Sandbox.Capability.NativeBuild.Context
  alias Kinda.Sandbox.Command.Spec
  alias Kinda.Sandbox.Error

  @impl true
  def stream(%State{context: %Context{} = context}, %Spec{} = spec) do
    if absolute_missing?(spec.executable) do
      {:error,
       Error.exception(
         reason: :backend_failure,
         backend: Kinda.Sandbox.Backend.LocalNative,
         operation: :command,
         message: "command executable does not exist",
         details: %{executable: spec.executable}
       )}
    else
      build_stream(context, spec)
    end
  end

  @impl true
  def terminate(worker, _reason) do
    case linked_command_process(worker) do
      nil ->
        :ok

      {:exile, process} ->
        terminate_exile(process)

      {:ex_cmd, process} ->
        terminate_ex_cmd(process, worker)
    end
  end

  defp build_stream(context, spec) do
    command = [spec.executable | spec.args]
    {events, streams} = process_stream(command, context, spec)

    metadata = %{
      streams: streams,
      process_tree_termination?: false,
      cwd: spec.cwd,
      executable: spec.executable
    }

    {:ok, Stream.concat([{:metadata, metadata}], events)}
  end

  defp process_stream(command, context, spec) do
    if windows?() do
      events =
        command
        |> ExCmd.stream(ex_cmd_options(context, spec))
        |> Stream.map(fn
          {:exit, {:status, status}} -> {:exit, status}
          {:exit, :epipe} -> {:signal, 0}
          data when is_binary(data) -> {:stdout, data}
        end)

      {events, :merged}
    else
      exile = Module.concat(["Exile"])

      events =
        command
        |> exile.stream(exile_options(context, spec))
        |> Stream.map(fn
          {:exit, {:status, status}} -> {:exit, status}
          {:exit, status} when is_integer(status) -> {:exit, status}
          {:exit, :epipe} -> {:signal, 0}
          {:stdout, data} -> {:stdout, data}
          {:stderr, data} -> {:stderr, data}
        end)

      {events, :separate}
    end
  end

  defp absolute_missing?(executable) do
    Path.type(executable) == :absolute and not File.regular?(executable)
  end

  defp ex_cmd_options(context, spec) do
    [
      cd: Path.join(context.directory, spec.cwd),
      env: environment(context.env, spec),
      input: input(spec.stdin),
      stderr: :redirect_to_stdout,
      max_chunk_size: 64 * 1024 - 5
    ]
  end

  defp exile_options(context, spec) do
    [
      cd: Path.join(context.directory, spec.cwd),
      env: environment(context.env, spec),
      input: exile_input(spec.stdin),
      stderr: :consume,
      max_chunk_size: 65_535
    ]
  end

  # ExCmd overlays the supplied environment. Empty overrides scrub ambient
  # values not selected by inherit_env without mutating global process state.
  defp environment(sandbox_env, spec) do
    scrubbed = Map.new(System.get_env(), fn {key, _value} -> {key, ""} end)

    inherited =
      spec.inherit_env
      |> Enum.flat_map(fn key ->
        case System.fetch_env(key) do
          {:ok, value} -> [{key, value}]
          :error -> []
        end
      end)
      |> Map.new()

    scrubbed
    |> Map.merge(sandbox_env)
    |> Map.merge(inherited)
    |> Map.merge(spec.env)
    |> Map.to_list()
  end

  defp input(:closed), do: []
  defp input(binary), do: binary
  defp exile_input(:closed), do: []
  defp exile_input(binary), do: [binary]

  defp linked_command_process(worker) do
    case Process.info(worker, :links) do
      {:links, links} -> Enum.find_value(links, &command_process/1)
      nil -> nil
    end
  end

  defp command_process(process) do
    case Process.info(process, :dictionary) do
      {:dictionary, dictionary} ->
        case List.keyfind(dictionary, :"$initial_call", 0) do
          {:"$initial_call", {Exile.Process, :init, 1}} -> {:exile, process}
          {:"$initial_call", {ExCmd.Process, :init, 1}} -> {:ex_cmd, process}
          _other -> nil
        end

      nil ->
        nil
    end
  end

  defp terminate_exile(process) do
    exile_process = Module.concat(["Exile", "Process"])
    handle = struct(exile_process, pid: process)
    if Process.alive?(process), do: exile_process.kill(handle, :sigkill)
    :ok
  end

  defp terminate_ex_cmd(process, worker) do
    monitor = Process.monitor(process)

    # ExCmd 0.18 has no public cross-process terminate call. This is its
    # bounded exit sequence, sent with the actual owner to close its pipes.
    GenServer.cast(process, {:prepare_exit, worker, 1_000})
    await_down(monitor, process, 1_500)
  end

  defp await_down(monitor, process, timeout) do
    receive do
      {:DOWN, ^monitor, :process, ^process, _reason} -> :ok
    after
      timeout ->
        Process.demonitor(monitor, [:flush])
        :ok
    end
  end

  defp windows?, do: match?({:win32, _name}, :os.type())
end
