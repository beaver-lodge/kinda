defmodule Kinda.Capsule.ExecutionServer do
  @moduledoc false

  use GenServer

  alias Kinda.Capsule.Error
  alias Kinda.Sandbox

  @enforce_keys [:ref, :capsule, :sandbox_execution]
  defstruct [
    :ref,
    :capsule,
    :sandbox_execution,
    :waiter,
    :waiter_monitor,
    result: nil,
    callers: []
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
    with_pid(ref, {:error, error(:disconnected)}, fn pid ->
      call(pid, {:await, timeout}, timeout_for_call(timeout), :await_timeout)
    end)
  end

  def cancel(ref) do
    with_pid(ref, :ok, fn pid -> call(pid, :cancel, :infinity, :disconnected) end)
  end

  def close(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      call(pid, :close, :infinity, :disconnected)
      |> case do
        {:error, %Error{reason: :disconnected}} -> :ok
        result -> result
      end
    else
      :ok
    end
  end

  @impl true
  def init(options) do
    state = %__MODULE__{
      ref: Keyword.fetch!(options, :ref),
      capsule: Keyword.fetch!(options, :capsule),
      sandbox_execution: Keyword.fetch!(options, :sandbox_execution)
    }

    server = self()

    waiter =
      spawn(fn ->
        send(server, {:sandbox_result, Sandbox.Command.await(state.sandbox_execution)})
      end)

    {:ok, %{state | waiter: waiter, waiter_monitor: Process.monitor(waiter)}}
  end

  @impl true
  def handle_call({:await, _timeout}, from, %{result: nil} = state) do
    {:noreply, %{state | callers: [from | state.callers]}}
  end

  def handle_call({:await, _timeout}, _from, state), do: {:reply, state.result, state}

  def handle_call(:cancel, _from, state) do
    reply =
      case Sandbox.Command.cancel(state.sandbox_execution) do
        {:error, %Sandbox.Error{} = cause} -> {:error, sandbox_error(cause)}
        result -> result
      end

    {:reply, reply, state}
  end

  def handle_call(:close, _from, state) do
    _result = Sandbox.Command.cancel(state.sandbox_execution)
    reply_callers(state.callers, {:error, error(:disconnected)})
    {:stop, :normal, :ok, %{state | callers: []}}
  end

  @impl true
  def handle_info({:sandbox_result, result}, state) do
    result = normalize_result(result)
    reply_callers(state.callers, result)
    send(state.capsule, {:capsule_execution_finished, state.ref, result})
    {:noreply, %{state | result: result, callers: []}}
  end

  def handle_info({:DOWN, monitor, :process, waiter, reason}, state)
      when monitor == state.waiter_monitor and waiter == state.waiter do
    if state.result do
      {:noreply, state}
    else
      result = {:error, Error.exception(phase: :execute, reason: :waiter_failure, cause: reason)}
      reply_callers(state.callers, result)
      send(state.capsule, {:capsule_execution_finished, state.ref, result})
      {:noreply, %{state | result: result, callers: []}}
    end
  end

  defp normalize_result({:ok, _result} = result), do: result
  defp normalize_result({:error, %Sandbox.Error{} = cause}), do: {:error, sandbox_error(cause)}

  defp reply_callers(callers, result), do: Enum.each(callers, &GenServer.reply(&1, result))

  defp with_pid(ref, missing, function) do
    case Registry.lookup(Kinda.Capsule.ExecutionRegistry, ref) do
      [{pid, _value}] -> function.(pid)
      [] -> missing
    end
  end

  defp call(pid, request, timeout, timeout_reason) do
    GenServer.call(pid, request, timeout)
  catch
    :exit, {:timeout, _details} -> {:error, error(timeout_reason)}
    :exit, _reason -> {:error, error(:disconnected)}
  end

  defp timeout_for_call(:infinity), do: :infinity
  defp timeout_for_call(timeout) when is_integer(timeout) and timeout >= 0, do: timeout
  defp timeout_for_call(_timeout), do: 0

  defp sandbox_error(cause) do
    Error.exception(phase: :execute, reason: :sandbox_failure, cause: cause)
  end

  defp error(reason), do: Error.exception(phase: :execute, reason: reason)

  defp via(ref), do: {:via, Registry, {Kinda.Capsule.ExecutionRegistry, ref}}
end
