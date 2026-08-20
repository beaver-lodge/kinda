defmodule Kinda.Sandbox.CommandContractBackend do
  @moduledoc false
  @behaviour Kinda.Sandbox.Backend

  @impl true
  def capabilities, do: %{command: __MODULE__.Command}

  @impl true
  def create(test_pid, _options) when is_pid(test_pid), do: {:ok, test_pid}

  @impl true
  def close(test_pid) do
    send(test_pid, :command_backend_closed)
    :ok
  end

  defmodule Command do
    @moduledoc false
    @behaviour Kinda.Sandbox.Capability.Command

    @impl true
    def stream(_test_pid, %{executable: "events"}) do
      {:ok, [{:stdout, "hello"}, {:stderr, "warning"}, {:exit, 7}]}
    end

    def stream(_test_pid, %{executable: "large"}) do
      {:ok, [{:stdout, "123456"}, {:stderr, "abcdef"}, {:exit, 0}]}
    end

    def stream(test_pid, %{executable: "block"}) do
      {:ok,
       Stream.resource(
         fn -> send(test_pid, {:command_worker, self()}) end,
         fn state -> receive(do: (:continue -> {[{:exit, 0}], state})) end,
         fn _state -> :ok end
       )}
    end
  end
end

defmodule Kinda.Sandbox.CommandContractUnsupportedBackend do
  @moduledoc false
  @behaviour Kinda.Sandbox.Backend

  @impl true
  def capabilities, do: %{}

  @impl true
  def create(:valid, _options), do: {:ok, :unsupported}

  @impl true
  def close(:unsupported), do: :ok
end

defmodule Kinda.Sandbox.CommandContractTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox
  alias Kinda.Sandbox.Command
  alias Kinda.Sandbox.Command.{Execution, Result, Spec}
  alias Kinda.Sandbox.Error

  test "validates a shell-free command specification before backend dispatch" do
    {:ok, handle} = Sandbox.create(Kinda.Sandbox.CommandContractBackend, self())

    assert {:error, %Error{reason: :invalid_spec}} =
             Command.start(handle, %Spec{executable: "ok", cwd: "../escape"})

    assert {:error, %Error{reason: :invalid_spec}} =
             Command.start(handle, %Spec{executable: "ok", args: ["bad\0arg"]})

    assert :ok = Sandbox.close(handle)
  end

  test "returns a ref-only execution handle and deterministic terminal result" do
    {:ok, handle} = Sandbox.create(Kinda.Sandbox.CommandContractBackend, self())
    assert {:ok, %Execution{} = execution} = Command.start(handle, %Spec{executable: "events"})
    assert Map.keys(Map.from_struct(execution)) == [:ref]

    assert {:ok, %Result{} = result} = Command.await(execution)
    assert result.termination == {:exit, 7}
    assert result.stdout == "hello"
    assert result.stderr == "warning"
    refute result.stdout_truncated?
    refute result.stderr_truncated?
    assert :ok = Sandbox.close(handle)
  end

  test "bounds stdout and stderr independently" do
    {:ok, handle} = Sandbox.create(Kinda.Sandbox.CommandContractBackend, self())

    assert {:ok, result} =
             Command.run(handle, %Spec{executable: "large", max_output_bytes: 3})

    assert result.stdout == "123"
    assert result.stderr == "abc"
    assert result.stdout_truncated?
    assert result.stderr_truncated?
    assert :ok = Sandbox.close(handle)
  end

  test "long command work does not block sandbox lifecycle calls and can be cancelled" do
    {:ok, handle} = Sandbox.create(Kinda.Sandbox.CommandContractBackend, self())
    {:ok, execution} = Command.start(handle, %Spec{executable: "block", timeout: :infinity})
    assert_receive {:command_worker, worker}

    assert {:ok, [:command]} = Sandbox.capabilities(handle)
    assert :ok = Command.cancel(execution)
    assert {:ok, %Result{termination: :cancelled}} = Command.await(execution)
    refute Process.alive?(worker)
    assert :ok = Sandbox.close(handle)
    assert_receive :command_backend_closed
  end

  test "unsupported backends report the command capability explicitly" do
    {:ok, handle} = Sandbox.create(Kinda.Sandbox.CommandContractUnsupportedBackend, :valid)

    assert {:error, %Error{reason: :unsupported_capability, operation: :command}} =
             Command.start(handle, %Spec{executable: "ignored"})

    assert :ok = Sandbox.close(handle)
  end
end
