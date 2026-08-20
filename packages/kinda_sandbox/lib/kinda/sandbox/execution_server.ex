defmodule Kinda.Sandbox.ExecutionServer do
  @moduledoc false

  use GenServer

  alias Kinda.Sandbox.Command.Result
  alias Kinda.Sandbox.Error

  defstruct [
    :ref,
    :backend,
    :capability,
    :backend_handle,
    :spec,
    :started_at,
    :worker,
    :worker_monitor,
    :backend_execution,
    :timer,
    stdout: "",
    stderr: "",
    stdout_truncated?: false,
    stderr_truncated?: false,
    metadata: %{},
    waiters: [],
    result: nil
  ]

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :ref)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def start_link(options) do
    ref = Keyword.fetch!(options, :ref)
    GenServer.start_link(__MODULE__, options, name: via(ref))
  end

  def await(ref, timeout) do
    case lookup(ref) do
      {:ok, pid} -> safe_call(pid, :await, timeout)
      :error -> disconnected(:command_await)
    end
  end

  def cancel(ref) do
    case lookup(ref) do
      {:ok, pid} -> safe_call(pid, :cancel, :infinity)
      :error -> disconnected(:command_cancel)
    end
  end

  def close(pid), do: GenServer.call(pid, :close, :infinity)

  @impl true
  def init(options) do
    spec = Keyword.fetch!(options, :spec)

    timer =
      if spec.timeout == :infinity,
        do: nil,
        else: Process.send_after(self(), :timeout, spec.timeout)

    state = %__MODULE__{
      ref: Keyword.fetch!(options, :ref),
      backend: Keyword.fetch!(options, :backend),
      capability: Keyword.fetch!(options, :capability),
      backend_handle: Keyword.fetch!(options, :backend_handle),
      spec: spec,
      started_at: System.monotonic_time(),
      timer: timer
    }

    {:ok, state, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state) do
    server = self()

    case Task.Supervisor.start_child(Kinda.Sandbox.CommandTaskSupervisor, fn ->
           run_stream(server, state)
         end) do
      {:ok, worker} ->
        {:noreply, %{state | worker: worker, worker_monitor: Process.monitor(worker)}}

      {:error, reason} ->
        {:noreply, finish(state, :spawn_failure, %{cause: reason})}
    end
  end

  @impl true
  def handle_call(:await, from, %{result: nil} = state),
    do: {:noreply, %{state | waiters: [from | state.waiters]}}

  def handle_call(:await, _from, state), do: {:reply, {:ok, state.result}, state}

  def handle_call(:cancel, _from, %{result: nil} = state) do
    stop_worker_and_wait(state, :cancelled)
    {:reply, :ok, finish(state, :cancelled)}
  end

  def handle_call(:cancel, _from, state), do: {:reply, :ok, state}

  def handle_call(:close, _from, state) do
    stop_worker_and_wait(state, :sandbox_closed)
    state = if state.result, do: state, else: finish(state, :cancelled)

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:command_event, worker, event_ref, event}, %{result: nil} = state) do
    state = consume(event, state)
    send(worker, {:command_ack, event_ref})
    {:noreply, state}
  end

  def handle_info(
        {:backend_execution, worker, registration_ref, backend_execution},
        %{result: nil} = state
      ) do
    send(worker, {:backend_execution_ack, registration_ref})
    {:noreply, %{state | backend_execution: backend_execution}}
  end

  def handle_info(
        {:backend_execution, worker, registration_ref, backend_execution},
        %{result: %Result{termination: termination}} = state
      ) do
    send(worker, {:backend_execution_ack, registration_ref})

    terminate_command(
      state.capability,
      backend_execution,
      termination,
      state.spec.terminate_after
    )

    {:noreply, state}
  end

  def handle_info({:command_event, worker, event_ref, _event}, state) do
    send(worker, {:command_ack, event_ref})
    {:noreply, state}
  end

  def handle_info({:command_error, %Error{} = error}, %{result: nil} = state) do
    {:noreply, finish(state, :spawn_failure, %{error: error})}
  end

  def handle_info({:command_error, %Error{}}, state), do: {:noreply, state}

  def handle_info(:command_complete, %{result: nil} = state),
    do: {:noreply, finish(state, :spawn_failure, %{cause: :missing_terminal_event})}

  def handle_info(:command_complete, state), do: {:noreply, state}

  def handle_info(:timeout, %{result: nil} = state) do
    stop_worker_and_wait(state, :timeout)
    {:noreply, finish(state, :timeout)}
  end

  def handle_info(:timeout, state), do: {:noreply, state}

  def handle_info(
        {:DOWN, monitor, :process, _pid, reason},
        %{worker_monitor: monitor, result: nil} = state
      ) do
    {:noreply, finish(state, :spawn_failure, %{cause: reason})}
  end

  def handle_info({:DOWN, _monitor, :process, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    stop_worker(state.worker)
    :ok
  end

  defp run_stream(server, state) do
    outcome =
      safely(fn ->
        case state.capability.stream(state.backend_handle, state.spec) do
          {:ok, enumerable} ->
            Enum.each(enumerable, &send_event(server, &1))

          {:ok, enumerable, backend_execution} ->
            register_backend_execution(server, backend_execution)
            Enum.each(enumerable, &send_event(server, &1))

          {:error, %Error{} = error} ->
            {:error, error}

          other ->
            {:invalid, other}
        end
      end)

    case outcome do
      :ok -> send(server, :command_complete)
      {:error, %Error{} = error} -> send(server, {:command_error, error})
      other -> send(server, {:command_error, backend_failure(state.backend, other)})
    end
  end

  defp consume({:stdout, data}, state), do: append(state, :stdout, data)
  defp consume({:stderr, data}, state), do: append(state, :stderr, data)

  defp consume({:metadata, metadata}, state) when is_map(metadata),
    do: %{state | metadata: Map.merge(state.metadata, metadata)}

  defp consume({:exit, status}, state) when is_integer(status) and status >= 0,
    do: finish(state, {:exit, status})

  defp consume({:signal, signal}, state) when is_integer(signal) and signal >= 0,
    do: finish(state, {:signal, signal})

  defp consume(event, state), do: finish(state, :spawn_failure, %{cause: {:invalid_event, event}})

  defp send_event(server, event) do
    event_ref = make_ref()
    send(server, {:command_event, self(), event_ref, event})

    receive do
      {:command_ack, ^event_ref} -> :ok
    end
  end

  defp register_backend_execution(server, backend_execution) do
    registration_ref = make_ref()
    send(server, {:backend_execution, self(), registration_ref, backend_execution})

    receive do
      {:backend_execution_ack, ^registration_ref} -> :ok
    end
  end

  defp append(state, stream, data) do
    data = IO.iodata_to_binary(data)
    current = Map.fetch!(state, stream)
    remaining = max(state.spec.max_output_bytes - byte_size(current), 0)
    accepted = binary_part(data, 0, min(byte_size(data), remaining))
    truncated? = byte_size(data) > remaining

    state
    |> Map.put(stream, current <> accepted)
    |> Map.update!(truncated_key(stream), &(&1 or truncated?))
  end

  defp truncated_key(:stdout), do: :stdout_truncated?
  defp truncated_key(:stderr), do: :stderr_truncated?

  defp finish(state, termination, metadata \\ %{}) do
    cancel_timer(state.timer)
    duration = System.monotonic_time() - state.started_at

    result = %Result{
      termination: termination,
      stdout: state.stdout,
      stderr: state.stderr,
      duration: duration,
      stdout_truncated?: state.stdout_truncated?,
      stderr_truncated?: state.stderr_truncated?,
      metadata: Map.merge(state.metadata, metadata)
    }

    emit(result, state.backend)
    Enum.each(state.waiters, &GenServer.reply(&1, {:ok, result}))
    %{state | result: result, waiters: [], timer: nil}
  end

  defp lookup(ref) do
    case Registry.lookup(Kinda.Sandbox.ExecutionRegistry, ref) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp via(ref), do: {:via, Registry, {Kinda.Sandbox.ExecutionRegistry, ref}}

  defp safe_call(pid, request, timeout) do
    GenServer.call(pid, request, timeout)
  catch
    :exit, _reason ->
      disconnected(if(request == :await, do: :command_await, else: :command_cancel))
  end

  defp disconnected(operation),
    do: {:error, Error.exception(reason: :disconnected, operation: operation)}

  defp stop_worker(nil), do: :ok
  defp stop_worker(pid), do: Process.exit(pid, :shutdown)

  defp stop_worker_and_wait(%{worker: nil}, _reason), do: :ok

  defp stop_worker_and_wait(state, reason) do
    pid = state.worker
    monitor = Process.monitor(pid)

    terminate_command(
      state.capability,
      state.backend_execution,
      reason,
      state.spec.terminate_after
    )

    stop_worker(pid)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
    after
      5_000 -> Process.demonitor(monitor, [:flush])
    end
  end

  defp terminate_command(capability, backend_execution, reason, grace_milliseconds) do
    if backend_execution != nil and function_exported?(capability, :terminate, 3) do
      _ = safely(fn -> capability.terminate(backend_execution, reason, grace_milliseconds) end)
    end

    :ok
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp safely(callback) do
    callback.()
  catch
    kind, reason -> {:caught, kind, reason, __STACKTRACE__}
  end

  defp backend_failure(backend, cause) do
    Error.exception(reason: :backend_failure, backend: backend, operation: :command, cause: cause)
  end

  defp emit(result, backend) do
    :telemetry.execute(
      [:kinda, :sandbox, :command],
      %{duration: result.duration},
      %{
        backend: backend,
        termination: termination_class(result.termination),
        stdout_truncated?: result.stdout_truncated?,
        stderr_truncated?: result.stderr_truncated?
      }
    )
  end

  defp termination_class({:exit, _status}), do: :exit
  defp termination_class({:signal, _signal}), do: :signal
  defp termination_class(termination), do: termination
end
