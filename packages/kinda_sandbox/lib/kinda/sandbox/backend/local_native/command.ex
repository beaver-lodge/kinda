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
    case linked_ex_cmd_process(worker) do
      nil ->
        :ok

      process ->
        monitor = Process.monitor(process)

        # ExCmd 0.18 has no public cross-process terminate call. This is the
        # same bounded exit sequence used by ExCmd.Process.await_exit/2, sent
        # with the actual owner so its pipes are closed before TERM/KILL.
        GenServer.cast(process, {:prepare_exit, worker, 1_000})

        receive do
          {:DOWN, ^monitor, :process, ^process, _reason} -> :ok
        after
          1_500 ->
            Process.demonitor(monitor, [:flush])
            :ok
        end
    end
  end

  defp build_stream(context, spec) do
    command = [spec.executable | spec.args]
    options = command_options(context, spec)

    events =
      command
      |> ExCmd.stream(options)
      |> Stream.map(fn
        {:exit, {:status, status}} -> {:exit, status}
        {:exit, :epipe} -> {:signal, 0}
        data when is_binary(data) -> {:stdout, data}
      end)

    metadata = %{
      streams: :merged,
      process_tree_termination?: false,
      cwd: spec.cwd,
      executable: spec.executable
    }

    {:ok, Stream.concat([{:metadata, metadata}], events)}
  end

  defp absolute_missing?(executable) do
    Path.type(executable) == :absolute and not File.regular?(executable)
  end

  defp command_options(context, spec) do
    [
      cd: Path.join(context.directory, spec.cwd),
      env: environment(context.env, spec),
      input: input(spec.stdin),
      stderr: :redirect_to_stdout,
      max_chunk_size: 64 * 1024 - 5
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

  defp linked_ex_cmd_process(worker) do
    case Process.info(worker, :links) do
      {:links, links} -> Enum.find(links, &ex_cmd_process?/1)
      nil -> nil
    end
  end

  defp ex_cmd_process?(process) do
    case Process.info(process, :dictionary) do
      {:dictionary, dictionary} ->
        List.keyfind(dictionary, :"$initial_call", 0) ==
          {:"$initial_call", {ExCmd.Process, :init, 1}}

      nil ->
        false
    end
  end
end
