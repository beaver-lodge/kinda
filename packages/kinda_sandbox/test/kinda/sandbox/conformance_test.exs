defmodule Kinda.Sandbox.Conformance do
  @moduledoc false

  import ExUnit.Assertions

  alias Kinda.Sandbox
  alias Kinda.Sandbox.Handle

  def verify!(backend, spec_factory, observe, assert_cleaned) do
    verify_explicit_close!(backend, spec_factory, observe, assert_cleaned)
    verify_owner_exit!(backend, spec_factory, observe, assert_cleaned)
  end

  defp verify_explicit_close!(backend, spec_factory, observe, assert_cleaned) do
    {:ok, %Handle{ref: ref} = handle} = Sandbox.create(backend, spec_factory.())
    token = observe.(handle)
    [{server, _value}] = Registry.lookup(Kinda.Sandbox.Registry, ref)
    monitor = Process.monitor(server)

    assert :ok = Sandbox.close(handle)
    assert_receive {:DOWN, ^monitor, :process, ^server, :normal}
    assert eventually(fn -> Registry.lookup(Kinda.Sandbox.Registry, ref) == [] end)
    assert_cleaned.(token)
    assert :ok = Sandbox.close(handle)
  end

  defp verify_owner_exit!(backend, spec_factory, observe, assert_cleaned) do
    test_pid = self()

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        {:ok, handle} = Sandbox.create(backend, spec_factory.())
        send(test_pid, {:conformance_handle, handle})
        receive(do: (:stop -> :ok))
      end)

    assert_receive {:conformance_handle, %Handle{ref: ref} = handle}
    token = observe.(handle)
    [{server, _value}] = Registry.lookup(Kinda.Sandbox.Registry, ref)
    server_monitor = Process.monitor(server)
    send(owner, :stop)

    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :normal}
    assert_receive {:DOWN, ^server_monitor, :process, ^server, reason}
    assert reason in [:normal, :noproc]
    assert eventually(fn -> Registry.lookup(Kinda.Sandbox.Registry, ref) == [] end)
    assert_cleaned.(token)
  end

  defp eventually(predicate, attempts \\ 100)

  defp eventually(predicate, attempts) when attempts > 0 do
    if predicate.() do
      true
    else
      Process.sleep(1)
      eventually(predicate, attempts - 1)
    end
  end

  defp eventually(_predicate, 0), do: false
end

defmodule Kinda.Sandbox.ConformanceFakeBackend do
  @moduledoc false
  @behaviour Kinda.Sandbox.Backend

  @impl true
  def capabilities, do: %{}

  @impl true
  def create(:valid, _options), do: {:ok, :fake}

  @impl true
  def close(:fake), do: :ok
end

defmodule Kinda.Sandbox.ConformanceTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox.Backend.LocalNative
  alias Kinda.Sandbox.Backend.LocalNative.Spec
  alias Kinda.Sandbox.Capability.NativeBuild.Context
  alias Kinda.Sandbox.{Conformance, NativeBuild}

  def observe_directory(test_pid, %Context{} = context) do
    artifact = Path.join(context.directory, "fixture.so")
    File.write!(artifact, "fixture")
    send(test_pid, {:conformance_directory, context.directory})
    artifact
  end

  test "fake backend passes the common lifecycle contract" do
    Conformance.verify!(
      Kinda.Sandbox.ConformanceFakeBackend,
      fn -> :valid end,
      fn _handle -> :no_external_resource end,
      fn :no_external_resource -> :ok end
    )
  end

  @tag :tmp_dir
  test "LocalNative passes the common lifecycle contract without directory leaks", %{
    tmp_dir: parent
  } do
    test_pid = self()

    Conformance.verify!(
      LocalNative,
      fn -> %Spec{base_module: __MODULE__, parent_directory: parent} end,
      fn handle ->
        {:ok, _artifact} =
          NativeBuild.build(handle, {__MODULE__, :observe_directory, [test_pid]})

        receive do
          {:conformance_directory, directory} -> directory
        end
      end,
      fn directory ->
        refute File.exists?(directory)
        assert File.dir?(parent)
      end
    )
  end
end
