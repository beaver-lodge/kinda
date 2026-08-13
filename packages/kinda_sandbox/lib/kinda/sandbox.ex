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
        {:ok, _pid} -> {:ok, Handle.new(ref)}
        {:error, %Error{} = error} -> {:error, error}
        {:error, reason} -> {:error, backend_error("could not start sandbox", reason)}
      end

    emit(:create, started_at, %{backend: backend, result: result_tag(result)})
    result
  end

  @spec close(Handle.t()) :: :ok | {:error, Error.t()}
  def close(%Handle{ref: ref}) do
    started_at = System.monotonic_time()
    result = call(ref, :close, :ok)
    emit(:close, started_at, %{result: result_tag(result)})
    result
  end

  @spec capabilities(Handle.t()) :: result([atom()])
  def capabilities(%Handle{ref: ref}), do: call(ref, :capabilities, disconnected())

  @spec transfer_owner(Handle.t(), pid()) :: :ok | {:error, Error.t()}
  def transfer_owner(%Handle{ref: ref}, owner) do
    call(ref, {:transfer_owner, owner}, disconnected())
  end

  @spec detach(Handle.t()) :: :ok | {:error, Error.t()}
  def detach(%Handle{ref: ref}), do: call(ref, :detach, disconnected())

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

  defp disconnected do
    {:error, Error.exception(reason: :disconnected)}
  end

  defp backend_error(message, details) do
    Error.exception(reason: :backend_failure, message: message, details: details)
  end

  defp result_tag({:ok, _value}), do: :ok
  defp result_tag(:ok), do: :ok
  defp result_tag({:error, %Error{reason: reason}}), do: {:error, reason}

  defp emit(event, started_at, metadata) do
    :telemetry.execute(
      [:kinda, :sandbox, event],
      %{duration: System.monotonic_time() - started_at},
      metadata
    )
  end
end
