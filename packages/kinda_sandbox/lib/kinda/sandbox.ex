defmodule Kinda.Sandbox do
  @moduledoc """
  Backend-neutral lifecycle facade for isolated execution environments.

  A handle is owned by the process that creates it. Owner termination closes
  the backend unless ownership is transferred or detached first.
  """

  alias Kinda.Sandbox.{Error, Handle, HandleServer}

  @type result(value) :: {:ok, value} | {:error, Error.t()}

  @spec create(module(), term(), keyword()) :: result(Handle.t())
  def create(backend, spec, options \\ []) when is_list(options) do
    started_at = System.monotonic_time()
    ref = make_ref()

    child_options = [ref: ref, backend: backend, spec: spec, owner: self()] ++ options

    result =
      case DynamicSupervisor.start_child(
             Kinda.Sandbox.HandleSupervisor,
             {HandleServer, child_options}
           ) do
        {:ok, pid} ->
          {:ok, Handle.new(ref), capability_keys(pid)}

        {:error, %Error{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, backend_error("could not start sandbox", reason, backend, :create)}
      end

    {public_result, capability_keys} = split_create_result(result)

    emit(:create, started_at, %{
      backend: backend,
      capabilities: capability_keys,
      outcome: result_tag(public_result)
    })

    public_result
  end

  @spec close(Handle.t()) :: :ok | {:error, Error.t()}
  def close(%Handle{ref: ref}) do
    started_at = System.monotonic_time()
    {result, metadata} = HandleServer.close(ref)
    emit(:close, started_at, Map.put(metadata, :outcome, result_tag(result)))
    result
  end

  @spec capabilities(Handle.t()) :: result([atom()])
  def capabilities(%Handle{ref: ref}), do: call(ref, :capabilities, disconnected(:capabilities))

  @spec transfer_owner(Handle.t(), pid()) :: :ok | {:error, Error.t()}
  def transfer_owner(%Handle{ref: ref}, owner) do
    call(ref, {:transfer_owner, owner}, disconnected(:transfer_owner))
  end

  @spec detach(Handle.t()) :: :ok | {:error, Error.t()}
  def detach(%Handle{ref: ref}), do: call(ref, :detach, disconnected(:detach))

  defp call(ref, request, missing_result) do
    case Registry.lookup(Kinda.Sandbox.Registry, ref) do
      [{pid, _value}] -> safe_call(pid, request, missing_result)
      [] -> missing_result
    end
  end

  defp safe_call(pid, request, disconnected_result) do
    GenServer.call(pid, request)
  catch
    :exit, _reason -> disconnected_result
  end

  defp disconnected(operation) do
    {:error, Error.exception(reason: :disconnected, operation: operation)}
  end

  defp backend_error(message, cause, backend, operation) do
    Error.exception(
      reason: :backend_failure,
      message: message,
      backend: backend,
      operation: operation,
      cause: cause
    )
  end

  defp result_tag({:ok, _value}), do: :ok
  defp result_tag(:ok), do: :ok
  defp result_tag({:error, %Error{reason: reason}}), do: {:error, reason}

  defp split_create_result({:ok, handle, capability_keys}), do: {{:ok, handle}, capability_keys}
  defp split_create_result({:error, %Error{} = error}), do: {{:error, error}, []}

  defp capability_keys(pid) do
    case GenServer.call(pid, :capabilities) do
      {:ok, capability_keys} -> capability_keys
    end
  end

  defp emit(event, started_at, metadata) do
    :telemetry.execute(
      [:kinda, :sandbox, event],
      %{duration: System.monotonic_time() - started_at},
      metadata
    )
  end
end
