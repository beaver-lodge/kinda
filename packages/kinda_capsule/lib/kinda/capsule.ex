defmodule Kinda.Capsule do
  @moduledoc """
  Owner-scoped typed episode orchestration built on `Kinda.Sandbox`.
  """

  alias Kinda.Capsule.Action.Command
  alias Kinda.Capsule.{Artifact, Episode, Error, Execution, ExecutionServer, Handle}
  alias Kinda.Capsule.{Observation, Score, Server, Spec, Trace}

  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @spec create(Spec.t()) :: result(Handle.t())
  def create(%Spec{} = spec) do
    with :ok <- Spec.validate(spec) do
      ref = make_ref()

      case DynamicSupervisor.start_child(
             Kinda.Capsule.ServerSupervisor,
             {Server, ref: ref, owner: self(), spec: spec}
           ) do
        {:ok, _pid} -> {:ok, Handle.new(ref)}
        {:error, reason} -> {:error, error(:create, :start_failure, reason)}
      end
    end
  end

  def create(spec), do: Spec.validate(spec)

  @spec reset(Handle.t(), keyword()) :: result(Observation.t())
  def reset(%Handle{ref: ref}, options) when is_list(options) do
    case Keyword.fetch(options, :seed) do
      {:ok, seed} -> call(ref, {:reset, seed}, :reset)
      :error -> {:error, error(:reset, :invalid_options, nil, "seed is required")}
    end
  end

  def reset(%Handle{}, _options),
    do: {:error, error(:reset, :invalid_options, nil, "options must be a keyword list")}

  @spec observe(Handle.t()) :: result(Observation.t())
  def observe(%Handle{ref: ref}), do: call(ref, :observe, :observe)

  @spec start(Handle.t(), Command.t()) :: result(Execution.t())
  def start(%Handle{ref: ref}, %Command{} = action),
    do: call(ref, {:start, action}, :execute)

  def start(%Handle{}, _action),
    do: {:error, error(:execute, :invalid_action, nil, "expected a command action")}

  @spec execute(Handle.t(), Command.t(), timeout()) ::
          result(Kinda.Sandbox.Command.Result.t())
  def execute(handle, action, await_timeout \\ :infinity) do
    with {:ok, execution} <- start(handle, action) do
      await(execution, await_timeout)
    end
  end

  @spec await(Execution.t(), timeout()) :: result(Kinda.Sandbox.Command.Result.t())
  def await(%Execution{ref: ref}, timeout \\ :infinity),
    do: ExecutionServer.await(ref, timeout)

  @spec cancel(Execution.t()) :: :ok | {:error, Error.t()}
  def cancel(%Execution{ref: ref}), do: ExecutionServer.cancel(ref)

  @spec trace(Handle.t()) :: result(Trace.t())
  def trace(%Handle{ref: ref}), do: call(ref, :trace, :trace)

  @spec episode(Handle.t()) :: result(Episode.t())
  def episode(%Handle{ref: ref}), do: call(ref, :episode, :trace)

  @spec attach_artifact(Handle.t(), Artifact.t()) :: :ok | {:error, Error.t()}
  def attach_artifact(%Handle{ref: ref}, %Artifact{} = artifact),
    do: call(ref, {:attach_artifact, artifact}, :artifact)

  def attach_artifact(%Handle{}, _artifact),
    do: {:error, error(:artifact, :invalid_artifact)}

  @spec grade(Handle.t()) :: result(Score.t())
  def grade(%Handle{ref: ref}), do: call(ref, :grade, :grade)

  @spec close(Handle.t()) :: :ok | {:error, Error.t()}
  def close(%Handle{ref: ref}) do
    case Registry.lookup(Kinda.Capsule.Registry, ref) do
      [{pid, _value}] ->
        case safe_call(pid, :close, :close) do
          {:error, %Error{reason: :disconnected}} -> :ok
          result -> result
        end

      [] ->
        :ok
    end
  end

  defp call(ref, request, phase) do
    case Registry.lookup(Kinda.Capsule.Registry, ref) do
      [{pid, _value}] -> safe_call(pid, request, phase)
      [] -> {:error, error(phase, :disconnected)}
    end
  end

  defp safe_call(pid, request, phase) do
    GenServer.call(pid, request, :infinity)
  catch
    :exit, _reason -> {:error, error(phase, :disconnected)}
  end

  defp error(phase, reason, cause \\ nil, message \\ "capsule operation failed") do
    Error.exception(phase: phase, reason: reason, cause: cause, message: message)
  end
end
