defmodule Kinda.Sandbox.Backend.LocalProcess.Command do
  @moduledoc false

  @behaviour Kinda.Sandbox.Capability.Command

  alias Kinda.Sandbox.Backend.LocalProcess
  alias Kinda.Sandbox.Backend.LocalProcess.State
  alias Kinda.Sandbox.Command.Spec
  alias Kinda.Sandbox.Error

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
      build_stream(state, spec)
    end
  end

  @impl true
  def terminate(worker, _reason) do
    case linked_command_process(worker) do
      nil -> :ok
      {:exile, process} -> terminate_exile(process)
      {:ex_cmd, process} -> terminate_ex_cmd(process, worker)
    end
  end

  defp build_stream(state, spec) do
    command = [spec.executable | spec.args]
    {events, streams} = process_stream(command, state, spec)

    metadata = %{
      streams: streams,
      process_tree_termination?: false,
      cwd: spec.cwd,
      executable: spec.executable
    }

    {:ok, Stream.concat([{:metadata, metadata}], events)}
  end

  defp process_stream(command, state, spec) do
    if windows?() do
      events =
        command
        |> ExCmd.stream(ex_cmd_options(state, spec))
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
        |> exile.stream(exile_options(state, spec))
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

  defp ex_cmd_options(state, spec) do
    [
      cd: Path.join(state.directory, spec.cwd),
      env: environment(state.env, spec),
      input: input(spec.stdin),
      stderr: :redirect_to_stdout,
      max_chunk_size: 64 * 1024 - 5
    ]
  end

  defp exile_options(state, spec) do
    [
      cd: Path.join(state.directory, spec.cwd),
      env: environment(state.env, spec),
      input: exile_input(spec.stdin),
      stderr: :consume,
      max_chunk_size: 65_535
    ]
  end

  defp environment(sandbox_env, spec) do
    ambient = normalize_environment(System.get_env())
    scrubbed = Map.new(ambient, fn {key, _value} -> {key, ""} end)

    inherited =
      spec.inherit_env
      |> Enum.map(&normalize_environment_key/1)
      |> Map.new(fn key -> {key, Map.get(ambient, key)} end)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    scrubbed
    |> Map.merge(normalize_environment(sandbox_env))
    |> Map.merge(inherited)
    |> Map.merge(normalize_environment(spec.env))
    |> Map.to_list()
  end

  defp normalize_environment(environment) do
    Map.new(environment, fn {key, value} -> {normalize_environment_key(key), value} end)
  end

  defp normalize_environment_key(key) do
    if windows?(), do: String.upcase(key), else: key
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
    _ = kill_windows_process_tree(process)
    GenServer.cast(process, {:prepare_exit, worker, 1_000})
    await_down(monitor, process, 1_500)
  end

  defp kill_windows_process_tree(process) do
    handle = struct(ExCmd.Process, pid: process)

    with {:ok, os_pid} <- ExCmd.Process.os_pid(handle),
         executable when is_binary(executable) <- System.find_executable("taskkill"),
         {_output, 0} <-
           System.cmd(executable, ["/PID", Integer.to_string(os_pid), "/T", "/F"],
             stderr_to_stdout: true
           ) do
      :ok
    else
      _error -> :not_available
    end
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
