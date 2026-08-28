defmodule Kinda.Sandbox.FakeBackend do
  @behaviour Kinda.Sandbox.Backend

  alias Kinda.Sandbox.Error

  @impl true
  def capabilities, do: %{fake: __MODULE__.Capability}

  @impl true
  def create({:notify, test_pid}, _options), do: {:ok, test_pid}

  def create(:invalid, _options), do: {:error, Error.exception(reason: :invalid_spec)}
  def create(:raise, _options), do: raise("create failed")

  @impl true
  def close(test_pid) do
    send(test_pid, {:backend_closed, self()})
    :ok
  end

  defmodule Capability do
    @moduledoc false
  end
end

defmodule Kinda.Sandbox.LifecycleTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox
  alias Kinda.Sandbox.{Error, FakeBackend, Handle, NativeBuild}

  def handle_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  test "creates a ref-only handle and reports capability keys" do
    assert {:ok, %Handle{} = handle} = Sandbox.create(FakeBackend, {:notify, self()})
    assert {:ok, [:fake]} = Sandbox.capabilities(handle)
    assert :ok = Sandbox.close(handle)
    assert_received {:backend_closed, _server}
  end

  test "close is idempotent" do
    {:ok, handle} = Sandbox.create(FakeBackend, {:notify, self()})

    assert :ok = Sandbox.close(handle)
    assert_received {:backend_closed, _server}
    assert :ok = Sandbox.close(handle)
    refute_received {:backend_closed, _server}
  end

  test "owner exit closes the backend" do
    parent = self()

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        {:ok, handle} = Sandbox.create(FakeBackend, {:notify, parent})
        send(parent, {:handle, handle})
        receive(do: (:stop -> :ok))
      end)

    handle = await_owner_result!(owner, owner_monitor, :handle)
    send(owner, :stop)
    await_down!(owner, owner_monitor, :normal)
    await_backend_close!()
    assert {:error, %Error{reason: :disconnected}} = Sandbox.capabilities(handle)
  end

  test "ownership transfer is serialized before the old owner exits" do
    parent = self()
    new_owner = spawn(fn -> receive(do: (:stop -> :ok)) end)

    {old_owner, old_monitor} =
      spawn_monitor(fn ->
        {:ok, handle} = Sandbox.create(FakeBackend, {:notify, parent})
        :ok = Sandbox.transfer_owner(handle, new_owner)
        send(parent, {:transferred, handle})
      end)

    handle = await_owner_result!(old_owner, old_monitor, :transferred)
    await_down!(old_owner, old_monitor, :normal)
    assert {:ok, [:fake]} = Sandbox.capabilities(handle)

    new_monitor = Process.monitor(new_owner)
    send(new_owner, :stop)
    await_down!(new_owner, new_monitor, :normal)
    await_backend_close!()
  end

  test "detached handles outlive their creator" do
    parent = self()

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        {:ok, handle} = Sandbox.create(FakeBackend, {:notify, parent})
        :ok = Sandbox.detach(handle)
        send(parent, {:detached, handle})
      end)

    handle = await_owner_result!(owner, owner_monitor, :detached)
    await_down!(owner, owner_monitor, :normal)
    assert {:ok, [:fake]} = Sandbox.capabilities(handle)
    assert :ok = Sandbox.close(handle)
    assert_received {:backend_closed, _server}
  end

  test "a forcibly killed handle server is disconnected without cleanup guarantees" do
    {:ok, %Handle{ref: ref} = handle} = Sandbox.create(FakeBackend, {:notify, self()})
    assert [{server, _value}] = Registry.lookup(Kinda.Sandbox.Registry, ref)

    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    await_down!(server, monitor, :killed)

    assert :ok = Sandbox.close(handle)
    assert {:error, %Error{reason: :disconnected}} = Sandbox.capabilities(handle)
    assert {:error, %Error{reason: :disconnected}} = Sandbox.detach(handle)
    assert {:error, %Error{reason: :disconnected}} = Sandbox.transfer_owner(handle, self())

    assert {:error, %Error{reason: :disconnected}} =
             NativeBuild.build(handle, {__MODULE__, :unused, []})

    refute_received {:backend_closed, _server}
  end

  test "normalizes invalid backends and create failures" do
    assert {:error, %Error{reason: :invalid_spec}} = Sandbox.create(FakeBackend, :invalid)
    assert {:error, %Error{reason: :backend_failure}} = Sandbox.create(FakeBackend, :raise)
    assert {:error, %Error{reason: :backend_failure}} = Sandbox.create(__MODULE__, :anything)
  end

  test "emits create and close telemetry only at the facade boundary" do
    handler_id = {__MODULE__, self()}
    events = [[:kinda, :sandbox, :create], [:kinda, :sandbox, :close]]

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, handle} = Sandbox.create(FakeBackend, {:notify, self()})

    assert_received {:telemetry, [:kinda, :sandbox, :create], %{duration: duration},
                     %{backend: FakeBackend, capabilities: [:fake], outcome: :ok}}

    assert is_integer(duration)

    :ok = Sandbox.close(handle)

    assert_received {:telemetry, [:kinda, :sandbox, :close], %{duration: _duration},
                     %{backend: FakeBackend, capabilities: [:fake], outcome: :ok}}
  end

  defp await_owner_result!(owner, monitor, tag) do
    receive do
      {^tag, handle} ->
        handle

      {:DOWN, ^monitor, :process, ^owner, reason} ->
        flunk("sandbox owner exited before publishing #{tag}: #{inspect(reason)}")
    end
  end

  defp await_down!(pid, monitor, reason) do
    receive do
      {:DOWN, ^monitor, :process, ^pid, ^reason} ->
        :ok

      {:DOWN, ^monitor, :process, ^pid, actual_reason} ->
        flunk("process exited with #{inspect(actual_reason)} instead of #{inspect(reason)}")
    end
  end

  defp await_backend_close! do
    receive do
      {:backend_closed, _server} -> :ok
    end
  end
end
