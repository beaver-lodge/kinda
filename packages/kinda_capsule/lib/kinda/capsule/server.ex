defmodule Kinda.Capsule.Server do
  @moduledoc false

  use GenServer

  alias Kinda.Capsule.{Context, Error, Observation, Trace}
  alias Kinda.Sandbox

  @enforce_keys [:ref, :capsule_id, :spec, :owner, :owner_monitor]
  defstruct [
    :ref,
    :capsule_id,
    :spec,
    :owner,
    :owner_monitor,
    :sandbox,
    :context,
    :task_state,
    :observation,
    :trace,
    status: :new
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

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)

    {:ok,
     %__MODULE__{
       ref: Keyword.fetch!(options, :ref),
       capsule_id: next_id(),
       spec: Keyword.fetch!(options, :spec),
       owner: owner,
       owner_monitor: Process.monitor(owner)
     }}
  end

  @impl true
  def handle_call({:reset, _seed}, _from, %{status: :running} = state) do
    {:reply, {:error, error(:reset, :busy)}, state}
  end

  def handle_call({:reset, seed}, _from, state) do
    case cleanup_current(state, :reset) do
      {:ok, clean_state} ->
        {reply, next_state} = start_episode(clean_state, seed)
        {:reply, reply, next_state}

      {{:error, cleanup_error}, clean_state} ->
        {:reply, {:error, cleanup_error}, clean_state}
    end
  end

  def handle_call(:observe, _from, %{status: :new} = state) do
    {:reply, {:error, error(:observe, :not_reset)}, state}
  end

  def handle_call(:observe, _from, %{status: :ready} = state) do
    case callback(state.spec.task, :observe, [state.context, state.task_state]) do
      {:ok, %Observation{metadata: metadata} = observation} when is_map(metadata) ->
        {:reply, {:ok, observation}, %{state | observation: observation}}

      {:error, reason} ->
        {:reply, {:error, callback_error(:observe, :task_error, reason)}, state}

      {:invalid, return} ->
        fail_untrusted_task(state, callback_error(:observe, :invalid_callback_return, return))

      {:raised, cause} ->
        fail_untrusted_task(state, callback_error(:observe, :callback_failure, cause))
    end
  end

  def handle_call(:close, _from, state) do
    {reply, clean_state} = cleanup_reply(cleanup_current(state, :close))
    {:stop, :normal, reply, clean_state}
  end

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, owner, _reason},
        %{owner_monitor: monitor, owner: owner} = state
      ) do
    {_result, clean_state} = cleanup_current(state, :close)
    {:stop, :normal, clean_state}
  end

  @impl true
  def terminate(_reason, state) do
    _result = cleanup_current(state, :close)
    :ok
  end

  defp start_episode(state, seed) do
    sandbox_spec = state.spec.sandbox

    case Sandbox.create(
           sandbox_spec.backend,
           sandbox_spec.backend_spec,
           sandbox_spec.backend_options
         ) do
      {:ok, sandbox} -> start_task(state, sandbox, seed)
      {:error, %Sandbox.Error{} = cause} -> reset_failure(state, sandbox_error(:reset, cause))
    end
  end

  defp start_task(state, sandbox, seed) do
    case Sandbox.capabilities(sandbox) do
      {:ok, capabilities} ->
        if :command in capabilities do
          reset_task(state, sandbox, seed)
        else
          primary =
            Error.exception(
              phase: :reset,
              reason: :unsupported_capability,
              details: %{required: :command, available: capabilities}
            )

          close_failed_reset(state, sandbox, nil, nil, primary)
        end

      {:error, %Sandbox.Error{} = cause} ->
        close_failed_reset(state, sandbox, nil, nil, sandbox_error(:reset, cause))
    end
  end

  defp reset_task(state, sandbox, seed) do
    context = %Context{capsule_id: state.capsule_id, sandbox: sandbox, seed: seed}

    case callback(state.spec.task, :reset, [context, seed, state.spec.task_options]) do
      {:ok, task_state, %Observation{metadata: metadata} = observation} when is_map(metadata) ->
        trace = %Trace{
          capsule_id: state.capsule_id,
          task_version: state.spec.task_version,
          verifier_version: state.spec.verifier_version,
          seed: seed
        }

        {{:ok, observation},
         %{
           state
           | sandbox: sandbox,
             context: context,
             task_state: task_state,
             observation: observation,
             trace: trace,
             status: :ready
         }}

      {:ok, task_state, invalid_observation} ->
        primary = callback_error(:reset, :invalid_callback_return, invalid_observation)
        close_failed_reset(state, sandbox, context, task_state, primary)

      {:error, reason} ->
        close_failed_reset(state, sandbox, nil, nil, callback_error(:reset, :task_error, reason))

      {:invalid, return} ->
        close_failed_reset(
          state,
          sandbox,
          nil,
          nil,
          callback_error(:reset, :invalid_callback_return, return)
        )

      {:raised, cause} ->
        close_failed_reset(
          state,
          sandbox,
          nil,
          nil,
          callback_error(:reset, :callback_failure, cause)
        )
    end
  end

  defp close_failed_reset(state, sandbox, context, task_state, primary) do
    if context && task_state do
      _result = close_task(state.spec.task, context, task_state, :reset)
    end

    _result = Sandbox.close(sandbox)
    reset_failure(state, primary)
  end

  defp reset_failure(state, error), do: {{:error, error}, clear_episode(state)}

  defp fail_untrusted_task(state, primary) do
    {_cleanup_result, clean_state} = cleanup_current(state, :observe)
    {:reply, {:error, primary}, clean_state}
  end

  defp cleanup_current(%{sandbox: nil} = state, _phase), do: {:ok, clear_episode(state)}

  defp cleanup_current(state, phase) do
    task_result = close_task(state.spec.task, state.context, state.task_state, phase)
    sandbox_result = Sandbox.close(state.sandbox)
    clean_state = clear_episode(state)

    case first_error(task_result, sandbox_result, phase) do
      nil -> {:ok, clean_state}
      error -> {{:error, error}, clean_state}
    end
  end

  defp close_task(_task, nil, _task_state, _phase), do: :ok
  defp close_task(_task, _context, nil, _phase), do: :ok

  defp close_task(task, context, task_state, phase) do
    case callback(task, :close, [context, task_state]) do
      :ok -> :ok
      {:error, reason} -> {:error, callback_error(phase, :task_cleanup_failed, reason)}
      {:invalid, return} -> {:error, callback_error(phase, :invalid_callback_return, return)}
      {:raised, cause} -> {:error, callback_error(phase, :callback_failure, cause)}
    end
  end

  defp first_error({:error, error}, _sandbox_result, _phase), do: error

  defp first_error(:ok, {:error, %Sandbox.Error{} = cause}, phase),
    do: sandbox_error(phase, cause)

  defp first_error(:ok, :ok, _phase), do: nil

  defp cleanup_reply({:ok, state}), do: {:ok, state}
  defp cleanup_reply({{:error, error}, state}), do: {{:error, error}, state}

  defp clear_episode(state) do
    %{
      state
      | sandbox: nil,
        context: nil,
        task_state: nil,
        observation: nil,
        trace: nil,
        status: :new
    }
  end

  defp callback(module, function, arguments) do
    apply(module, function, arguments)
  rescue
    exception -> {:raised, {:error, exception}}
  catch
    kind, reason -> {:raised, {kind, reason}}
  else
    result -> normalize_callback(result)
  end

  defp normalize_callback(:ok), do: :ok
  defp normalize_callback({:ok, _value} = result), do: result
  defp normalize_callback({:ok, _state, _value} = result), do: result
  defp normalize_callback({:error, _reason} = result), do: result
  defp normalize_callback(other), do: {:invalid, other}

  defp callback_error(phase, reason, cause) do
    Error.exception(phase: phase, reason: reason, cause: cause)
  end

  defp sandbox_error(phase, cause) do
    Error.exception(phase: phase, reason: :sandbox_failure, cause: cause)
  end

  defp error(phase, reason), do: Error.exception(phase: phase, reason: reason)

  defp next_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
  end

  defp via(ref), do: {:via, Registry, {Kinda.Capsule.Registry, ref}}
end
