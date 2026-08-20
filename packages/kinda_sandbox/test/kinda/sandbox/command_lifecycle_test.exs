defmodule Kinda.Sandbox.CommandLifecycleTelemetryBackend do
  @moduledoc false
  @behaviour Kinda.Sandbox.Backend

  @impl true
  def capabilities, do: %{command: __MODULE__.Command}

  @impl true
  def create(:telemetry, _options), do: {:ok, :telemetry}

  @impl true
  def close(:telemetry), do: :ok

  defmodule Command do
    @moduledoc false
    @behaviour Kinda.Sandbox.Capability.Command

    @impl true
    def stream(:telemetry, _spec), do: {:ok, [{:stdout, "captured"}, {:exit, 0}]}
  end
end

defmodule Kinda.Sandbox.CommandLifecycleTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox
  alias Kinda.Sandbox.Backend.LocalProcess
  alias Kinda.Sandbox.Backend.LocalProcess.Spec, as: BackendSpec
  alias Kinda.Sandbox.Command
  alias Kinda.Sandbox.Command.{Execution, Result, Spec}
  alias Kinda.Sandbox.Error

  def handle_telemetry(event, measurements, %{backend: backend} = metadata, {test_pid, backend}) do
    send(test_pid, {:command_telemetry, event, measurements, metadata})
  end

  def handle_telemetry(_event, _measurements, _metadata, _handler_config), do: :ok

  @tag :tmp_dir
  test "timeout terminates the external process before it can perform later work", %{
    tmp_dir: parent
  } do
    {:ok, sandbox} = Sandbox.create(LocalProcess, backend_spec(parent))

    spec = late_write_spec()

    assert {:ok, %Result{termination: :timeout}} = Command.run(sandbox, spec)
    Process.sleep(400)
    assert Path.wildcard(Path.join(parent, "kinda-process-*/late")) == []
    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "cancel is idempotent and leaves a stable terminal result", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalProcess, backend_spec(parent))

    {:ok, execution} =
      Command.start(sandbox, long_running_spec())

    assert :ok = Command.cancel(execution)
    assert :ok = Command.cancel(execution)
    assert {:ok, %Result{termination: :cancelled}} = Command.await(execution)
    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "sandbox close stops live executions and removes their handles and directory", %{
    tmp_dir: parent
  } do
    {:ok, sandbox} = Sandbox.create(LocalProcess, backend_spec(parent))
    directory = command_cwd(sandbox)

    {:ok, %Execution{} = execution} =
      Command.start(sandbox, long_running_spec())

    assert :ok = Sandbox.close(sandbox)
    refute File.exists?(directory)
    assert {:error, %Error{reason: :disconnected}} = Command.await(execution)
    assert {:error, %Error{reason: :disconnected}} = Command.cancel(execution)
  end

  @tag :tmp_dir
  test "owner exit stops live executions before backend cleanup", %{tmp_dir: parent} do
    test_pid = self()

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        {:ok, sandbox} = Sandbox.create(LocalProcess, backend_spec(parent))
        directory = command_cwd(sandbox)

        {:ok, execution} =
          Command.start(sandbox, long_running_spec())

        send(test_pid, {:owner_execution, execution, directory})
        receive(do: (:stop -> :ok))
      end)

    assert_receive {:owner_execution, execution, directory}, 5_000
    send(owner, :stop)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :normal}
    assert eventually(fn -> not File.exists?(directory) end)
    assert {:error, %Error{reason: :disconnected}} = Command.await(execution)
  end

  test "command telemetry reports lifecycle facts without command data" do
    handler_id = {__MODULE__, self()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:kinda, :sandbox, :command],
        &__MODULE__.handle_telemetry/4,
        {self(), Kinda.Sandbox.CommandLifecycleTelemetryBackend}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    {:ok, sandbox} = Sandbox.create(Kinda.Sandbox.CommandLifecycleTelemetryBackend, :telemetry)

    assert {:ok, _result} =
             Command.run(sandbox, %Spec{
               executable: "events",
               args: ["secret-argument"],
               env: %{"TOKEN" => "secret-value"},
               stdin: "secret-input"
             })

    assert_receive {:command_telemetry, [:kinda, :sandbox, :command], %{duration: duration},
                    metadata}

    assert is_integer(duration)

    assert metadata == %{
             backend: Kinda.Sandbox.CommandLifecycleTelemetryBackend,
             termination: :exit,
             stdout_truncated?: false,
             stderr_truncated?: false
           }

    refute inspect(metadata) =~ "secret"
    assert :ok = Sandbox.close(sandbox)
  end

  defp command_cwd(sandbox) do
    {:ok, result} =
      Command.run(sandbox, %Spec{
        executable: erl(),
        args: [
          "-noshell",
          "-eval",
          ~S|{ok, Cwd} = file:get_cwd(), io:put_chars(Cwd), halt().|
        ],
        env: base_env(),
        inherit_env: runtime_env()
      })

    result.stdout
  end

  defp backend_spec(parent), do: %BackendSpec{parent_directory: parent}

  defp late_write_spec do
    if windows?() do
      %Spec{
        executable: erl(),
        args: [
          "-noshell",
          "-eval",
          ~S|timer:sleep(300), file:write_file("late", <<"leaked">>), halt().|
        ],
        env: base_env(),
        inherit_env: runtime_env(),
        timeout: 25
      }
    else
      %Spec{
        executable: System.find_executable("sh") || raise("sh executable unavailable"),
        args: ["-c", "sleep 0.3; printf leaked > late"],
        env: base_env(),
        inherit_env: runtime_env(),
        timeout: 25
      }
    end
  end

  defp long_running_spec do
    if windows?() do
      %Spec{
        executable: erl(),
        args: ["-noshell", "-eval", "timer:sleep(infinity), halt()."],
        env: base_env(),
        inherit_env: runtime_env(),
        timeout: :infinity
      }
    else
      %Spec{
        executable: System.find_executable("sleep") || raise("sleep executable unavailable"),
        args: ["3600"],
        env: base_env(),
        inherit_env: runtime_env(),
        timeout: :infinity
      }
    end
  end

  defp base_env, do: %{"LANG" => "C.UTF-8"}
  defp erl, do: System.find_executable("erl") || raise("erl executable unavailable")

  defp runtime_env do
    ["PATH", "SYSTEMROOT", "SystemRoot", "COMSPEC", "ComSpec", "PATHEXT", "TEMP", "TMP"]
  end

  defp windows?, do: match?({:win32, _name}, :os.type())

  defp eventually(predicate, attempts \\ 200)
  defp eventually(_predicate, 0), do: false

  defp eventually(predicate, attempts) do
    if predicate.() do
      true
    else
      Process.sleep(5)
      eventually(predicate, attempts - 1)
    end
  end
end
