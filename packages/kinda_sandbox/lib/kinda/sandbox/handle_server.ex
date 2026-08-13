defmodule Kinda.Sandbox.HandleServer do
  @moduledoc false

  use GenServer

  alias Kinda.Sandbox.Error

  defstruct [:backend, :backend_handle, :capabilities, :owner, :owner_monitor, closed?: false]

  @type state :: %__MODULE__{
          backend: module(),
          backend_handle: term(),
          capabilities: %{optional(atom()) => module()},
          owner: pid() | nil,
          owner_monitor: reference() | nil,
          closed?: boolean()
        }

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :ref)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    ref = Keyword.fetch!(options, :ref)
    GenServer.start_link(__MODULE__, options, name: via(ref))
  end

  @spec via(reference()) :: GenServer.name()
  def via(ref), do: {:via, Registry, {Kinda.Sandbox.Registry, ref}}

  @spec native_build(reference(), Kinda.Sandbox.Capability.NativeBuild.builder_mfa()) ::
          {:ok, binary()} | {:error, Error.t()}
  def native_build(ref, builder_mfa) do
    call(ref, {:native_build, builder_mfa})
  end

  @impl true
  def init(options) do
    backend = Keyword.fetch!(options, :backend)
    owner = Keyword.fetch!(options, :owner)

    with {:ok, capabilities} <- backend_capabilities(backend),
         {:ok, backend_handle} <- backend_create(backend, Keyword.fetch!(options, :spec), options) do
      owner_monitor = Process.monitor(owner)

      {:ok,
       %__MODULE__{
         backend: backend,
         backend_handle: backend_handle,
         capabilities: capabilities,
         owner: owner,
         owner_monitor: owner_monitor
       }}
    else
      {:error, %Error{} = error} -> {:stop, error}
    end
  end

  @impl true
  def handle_call(:capabilities, _from, state) do
    {:reply, {:ok, state.capabilities |> Map.keys() |> Enum.sort()}, state}
  end

  def handle_call({:transfer_owner, owner}, _from, state) when is_pid(owner) do
    if Process.alive?(owner) do
      demonitor(state.owner_monitor)
      monitor = Process.monitor(owner)
      {:reply, :ok, %{state | owner: owner, owner_monitor: monitor}}
    else
      {:reply, {:error, invalid_owner_error()}, state}
    end
  end

  def handle_call({:transfer_owner, _owner}, _from, state) do
    {:reply, {:error, invalid_owner_error()}, state}
  end

  def handle_call(:detach, _from, state) do
    demonitor(state.owner_monitor)
    {:reply, :ok, %{state | owner: nil, owner_monitor: nil}}
  end

  def handle_call({:native_build, builder_mfa}, _from, state) do
    reply =
      case Map.fetch(state.capabilities, :native_build) do
        {:ok, capability} -> safely_native_build(capability, state.backend_handle, builder_mfa)
        :error -> {:error, Error.exception(reason: :unsupported_capability)}
      end

    {:reply, reply, state}
  end

  def handle_call(:close, _from, state) do
    {reply, state} = close_backend(state)
    {:stop, :normal, reply, state}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, owner, _reason}, %__MODULE__{} = state)
      when monitor == state.owner_monitor and owner == state.owner do
    {_reply, state} = close_backend(state)
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %__MODULE__{closed?: false} = state) do
    _ = close_backend(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp backend_capabilities(backend) when is_atom(backend) do
    if Code.ensure_loaded?(backend) and function_exported?(backend, :capabilities, 0) and
         function_exported?(backend, :create, 2) and function_exported?(backend, :close, 1) do
      case safely(fn -> backend.capabilities() end) do
        capabilities when is_map(capabilities) -> {:ok, capabilities}
        other -> {:error, backend_error("backend returned invalid capabilities", other)}
      end
    else
      {:error, backend_error("backend does not implement Kinda.Sandbox.Backend", backend)}
    end
  end

  defp backend_capabilities(backend) do
    {:error, backend_error("backend must be a module", backend)}
  end

  defp backend_create(backend, spec, options) do
    backend_options = Keyword.drop(options, [:backend, :owner, :ref, :spec])

    case safely(fn -> backend.create(spec, backend_options) end) do
      {:ok, backend_handle} -> {:ok, backend_handle}
      {:error, %Error{} = error} -> {:error, error}
      other -> {:error, backend_error("backend returned an invalid create result", other)}
    end
  end

  defp safely_native_build(capability, backend_handle, builder_mfa) do
    case safely(fn -> capability.build(backend_handle, builder_mfa) end) do
      {:ok, artifact} when is_binary(artifact) ->
        {:ok, artifact}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error, backend_error("native build capability returned an invalid result", other)}
    end
  end

  defp call(ref, request) do
    case Registry.lookup(Kinda.Sandbox.Registry, ref) do
      [{pid, _value}] -> safe_server_call(pid, request)
      [] -> disconnected()
    end
  end

  defp safe_server_call(pid, request) do
    GenServer.call(pid, request)
  catch
    :exit, _reason -> disconnected()
  end

  defp disconnected, do: {:error, Error.exception(reason: :disconnected)}

  defp close_backend(%__MODULE__{closed?: true} = state), do: {:ok, state}

  defp close_backend(state) do
    reply =
      case safely(fn -> state.backend.close(state.backend_handle) end) do
        :ok -> :ok
        {:error, %Error{} = error} -> {:error, error}
        other -> {:error, backend_error("backend returned an invalid close result", other)}
      end

    {reply, %{state | closed?: true}}
  end

  defp safely(callback) do
    callback.()
  catch
    kind, reason -> {:caught, kind, reason, __STACKTRACE__}
  end

  defp demonitor(nil), do: :ok
  defp demonitor(monitor), do: Process.demonitor(monitor, [:flush])

  defp invalid_owner_error do
    Error.exception(reason: :invalid_spec, message: "owner must be a live pid")
  end

  defp backend_error(message, details) do
    Error.exception(reason: :backend_failure, message: message, details: details)
  end
end
