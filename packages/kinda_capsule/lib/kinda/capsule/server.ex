defmodule Kinda.Capsule.Server do
  @moduledoc false

  use GenServer

  alias Kinda.Capsule.Action.Command
  alias Kinda.Capsule.{CommandSummary, Context, Error, Execution, ExecutionServer}
  alias Kinda.Capsule.{Observation, Step, Trace}
  alias Kinda.Sandbox
  alias Kinda.Sandbox.Command, as: SandboxCommand

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
    :active_execution,
    executions: %{},
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

  def handle_call(:observe, _from, %{status: :running} = state) do
    {:reply, {:error, error(:observe, :busy)}, state}
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

  def handle_call({:start, _action}, _from, %{status: :new} = state) do
    {:reply, {:error, error(:execute, :not_reset)}, state}
  end

  def handle_call({:start, _action}, _from, %{status: :running} = state) do
    {:reply, {:error, error(:execute, :busy)}, state}
  end

  def handle_call({:start, action}, _from, %{status: :ready} = state) do
    if length(state.trace.steps) >= state.spec.max_steps do
      {:reply, {:error, error(:execute, :step_limit)}, state}
    else
      case start_command(state, action) do
        {:ok, execution, next_state} -> {:reply, {:ok, execution}, next_state}
        {:error, execution_error} -> {:reply, {:error, execution_error}, state}
      end
    end
  end

  def handle_call(:trace, _from, %{status: :new} = state) do
    {:reply, {:error, error(:trace, :not_reset)}, state}
  end

  def handle_call(:trace, _from, state), do: {:reply, {:ok, state.trace}, state}

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

  def handle_info({:capsule_execution_finished, ref, {:ok, result}}, state) do
    if state.active_execution == ref do
      action = state.executions |> Map.fetch!(ref) |> Map.fetch!(:action)
      step = project_step(state, action, result)
      trace = %{state.trace | steps: state.trace.steps ++ [step], score: nil}

      {:noreply, %{state | active_execution: nil, trace: trace, status: :ready, observation: nil}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:capsule_execution_finished, ref, {:error, _error}}, state) do
    if state.active_execution == ref do
      {:noreply, %{state | active_execution: nil, status: :ready, observation: nil}}
    else
      {:noreply, state}
    end
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

  defp start_command(state, %Command{spec: command_spec, metadata: metadata} = action)
       when is_map(metadata) do
    with :ok <- SandboxCommand.Spec.validate(command_spec),
         {:ok, sandbox_execution} <- SandboxCommand.start(state.sandbox, command_spec) do
      ref = make_ref()
      options = [ref: ref, capsule: self(), sandbox_execution: sandbox_execution]

      case DynamicSupervisor.start_child(
             Kinda.Capsule.ExecutionSupervisor,
             {ExecutionServer, options}
           ) do
        {:ok, pid} ->
          entry = %{pid: pid, action: action}

          next_state = %{
            state
            | active_execution: ref,
              executions: Map.put(state.executions, ref, entry),
              status: :running
          }

          {:ok, Execution.new(ref), next_state}

        {:error, reason} ->
          _result = SandboxCommand.cancel(sandbox_execution)
          {:error, Error.exception(phase: :execute, reason: :start_failure, cause: reason)}
      end
    else
      {:error, %Sandbox.Error{} = cause} ->
        {:error, Error.exception(phase: :execute, reason: cause.reason, cause: cause)}
    end
  end

  defp start_command(_state, _action) do
    {:error,
     Error.exception(
       phase: :execute,
       reason: :invalid_action,
       message: "command action metadata must be a map"
     )}
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
    execution_result = close_executions(state.executions, phase)
    task_result = close_task(state.spec.task, state.context, state.task_state, phase)
    sandbox_result = Sandbox.close(state.sandbox)
    clean_state = clear_episode(state)

    case first_error(execution_result, task_result, sandbox_result, phase) do
      nil -> {:ok, clean_state}
      cleanup_error -> {{:error, cleanup_error}, clean_state}
    end
  end

  defp close_executions(executions, phase) do
    Enum.reduce(executions, :ok, fn {_ref, %{pid: pid}}, first_result ->
      case ExecutionServer.close(pid) do
        :ok ->
          first_result

        {:error, execution_error} when first_result == :ok ->
          {:error, %{execution_error | phase: phase}}

        {:error, _execution_error} ->
          first_result
      end
    end)
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

  defp first_error({:error, execution_error}, _task_result, _sandbox_result, _phase),
    do: execution_error

  defp first_error(:ok, {:error, task_error}, _sandbox_result, _phase), do: task_error

  defp first_error(:ok, :ok, {:error, %Sandbox.Error{} = cause}, phase),
    do: sandbox_error(phase, cause)

  defp first_error(:ok, :ok, :ok, _phase), do: nil

  defp cleanup_reply({:ok, state}), do: {:ok, state}
  defp cleanup_reply({{:error, cleanup_error}, state}), do: {{:error, cleanup_error}, state}

  defp clear_episode(state) do
    %{
      state
      | sandbox: nil,
        context: nil,
        task_state: nil,
        observation: nil,
        trace: nil,
        active_execution: nil,
        executions: %{},
        status: :new
    }
  end

  defp project_step(state, action, result) do
    spec = action.spec

    summary = %CommandSummary{
      executable: spec.executable,
      args: spec.args,
      cwd: spec.cwd,
      env_keys: spec.env |> Map.keys() |> Enum.sort(),
      inherit_env: Enum.sort(spec.inherit_env),
      stdin_bytes: if(is_binary(spec.stdin), do: byte_size(spec.stdin), else: 0)
    }

    %Step{
      sequence: length(state.trace.steps),
      action: summary,
      termination: result.termination,
      stdout: result.stdout,
      stderr: result.stderr,
      duration: result.duration,
      stdout_truncated?: result.stdout_truncated?,
      stderr_truncated?: result.stderr_truncated?,
      metadata: action.metadata
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
