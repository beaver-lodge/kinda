defmodule Kinda.Sandbox.HandleServer do
  @moduledoc false

  use GenServer

  alias Kinda.Sandbox.Command.{Execution, Spec}
  alias Kinda.Sandbox.{Error, ExecutionServer}

  defstruct [
    :backend,
    :backend_handle,
    :capabilities,
    :owner,
    :owner_monitor,
    closed?: false,
    executions: %{}
  ]

  @type state :: %__MODULE__{
          backend: module(),
          backend_handle: term(),
          capabilities: %{optional(atom()) => module()},
          owner: pid() | nil,
          owner_monitor: reference() | nil,
          closed?: boolean(),
          executions: %{optional(reference()) => pid()}
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

  @spec command(reference(), Spec.t()) :: {:ok, Execution.t()} | {:error, Error.t()}
  def command(ref, spec), do: call(ref, {:command, spec})

  @spec close(reference()) ::
          {:ok | {:error, Error.t()}, %{backend: module() | nil, capabilities: [atom()]}}
  def close(ref) do
    metadata = %{backend: nil, capabilities: []}

    case Registry.lookup(Kinda.Sandbox.Registry, ref) do
      [{pid, _value}] -> safe_close_call(pid, metadata)
      [] -> {:ok, metadata}
    end
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
        {:ok, capability} ->
          safely_native_build(state.backend, capability, state.backend_handle, builder_mfa)

        :error ->
          {:error,
           Error.exception(
             reason: :unsupported_capability,
             backend: state.backend,
             operation: :native_build
           )}
      end

    {:reply, reply, state}
  end

  def handle_call({:command, spec}, _from, state) do
    case Map.fetch(state.capabilities, :command) do
      {:ok, capability} ->
        ref = make_ref()

        options = [
          ref: ref,
          backend: state.backend,
          capability: capability,
          backend_handle: state.backend_handle,
          spec: spec
        ]

        case DynamicSupervisor.start_child(
               Kinda.Sandbox.ExecutionSupervisor,
               {ExecutionServer, options}
             ) do
          {:ok, pid} ->
            monitor = Process.monitor(pid)

            {:reply, {:ok, Execution.new(ref)},
             %{state | executions: Map.put(state.executions, monitor, pid)}}

          {:error, reason} ->
            {:reply,
             {:error,
              backend_error("could not start command execution", reason, state.backend, :command)},
             state}
        end

      :error ->
        error =
          Error.exception(
            reason: :unsupported_capability,
            backend: state.backend,
            operation: :command
          )

        {:reply, {:error, error}, state}
    end
  end

  def handle_call(:close_with_metadata, _from, state) do
    metadata = %{
      backend: state.backend,
      capabilities: state.capabilities |> Map.keys() |> Enum.sort()
    }

    {reply, state} = close_backend(state)
    {:stop, :normal, {reply, metadata}, state}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, owner, _reason}, %__MODULE__{} = state)
      when monitor == state.owner_monitor and owner == state.owner do
    {_reply, state} = close_backend(state)
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    {:noreply, %{state | executions: Map.delete(state.executions, monitor)}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %__MODULE__{closed?: false} = state) do
    _ = close_backend(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp backend_capabilities(backend) when is_atom(backend) do
    if Code.ensure_loaded?(backend) do
      case safely(fn -> backend.capabilities() end) do
        capabilities when is_map(capabilities) ->
          {:ok, capabilities}

        other ->
          {:error,
           backend_error("backend returned invalid capabilities", other, backend, :capabilities)}
      end
    else
      {:error,
       backend_error(
         "backend does not implement Kinda.Sandbox.Backend",
         :not_loaded,
         backend,
         :capabilities
       )}
    end
  end

  defp backend_capabilities(backend) do
    {:error, backend_error("backend must be a module", backend, nil, :capabilities)}
  end

  defp backend_create(backend, spec, options) do
    backend_options = Keyword.drop(options, [:backend, :owner, :ref, :spec])

    case safely(fn -> backend.create(spec, backend_options) end) do
      {:ok, backend_handle} ->
        {:ok, backend_handle}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error,
         backend_error("backend returned an invalid create result", other, backend, :create)}
    end
  end

  defp safely_native_build(backend, capability, backend_handle, builder_mfa) do
    case safely(fn -> capability.build(backend_handle, builder_mfa) end) do
      {:ok, artifact} when is_binary(artifact) ->
        {:ok, artifact}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error,
         backend_error(
           "native build capability returned an invalid result",
           other,
           backend,
           :native_build
         )}
    end
  end

  defp safe_close_call(pid, metadata) do
    GenServer.call(pid, :close_with_metadata)
  catch
    :exit, _reason -> {:ok, metadata}
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

  defp disconnected do
    {:error, Error.exception(reason: :disconnected)}
  end

  defp close_backend(%__MODULE__{closed?: true} = state), do: {:ok, state}

  defp close_backend(state) do
    Enum.each(state.executions, fn {_monitor, pid} ->
      if Process.alive?(pid), do: ExecutionServer.close(pid)
    end)

    reply =
      case safely(fn -> state.backend.close(state.backend_handle) end) do
        :ok ->
          :ok

        {:error, %Error{} = error} ->
          {:error, error}

        other ->
          {:error,
           backend_error(
             "backend returned an invalid close result",
             other,
             state.backend,
             :close
           )}
      end

    {reply, %{state | closed?: true, executions: %{}}}
  end

  defp safely(callback) do
    callback.()
  catch
    kind, reason -> {:caught, kind, reason, __STACKTRACE__}
  end

  defp demonitor(nil), do: :ok
  defp demonitor(monitor), do: Process.demonitor(monitor, [:flush])

  defp invalid_owner_error do
    Error.exception(
      reason: :invalid_spec,
      operation: :transfer_owner,
      message: "owner must be a live pid"
    )
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
end
