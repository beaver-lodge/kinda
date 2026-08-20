defmodule Kinda.Sandbox.CommandLifecycleTest do
  use ExUnit.Case, async: true

  alias Kinda.Sandbox
  alias Kinda.Sandbox.Backend.LocalNative
  alias Kinda.Sandbox.Backend.LocalNative.Spec, as: BackendSpec
  alias Kinda.Sandbox.Command
  alias Kinda.Sandbox.Command.{Execution, Result, Spec}
  alias Kinda.Sandbox.Error

  def handle_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:command_telemetry, event, measurements, metadata})
  end

  @tag :tmp_dir
  test "timeout terminates the external process before it can perform later work", %{
    tmp_dir: parent
  } do
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))

    spec = %Spec{
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

    assert {:ok, %Result{termination: :timeout}} = Command.run(sandbox, spec)
    Process.sleep(400)
    refute Path.wildcard(Path.join(parent, "kinda-sandbox-*/late")) != []
    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "cancel is idempotent and leaves a stable terminal result", %{tmp_dir: parent} do
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))

    {:ok, execution} =
      Command.start(sandbox, %Spec{
        executable: erl(),
        args: ["-noshell", "-eval", "timer:sleep(infinity), halt()."],
        env: base_env(),
        inherit_env: runtime_env(),
        timeout: :infinity
      })

    assert :ok = Command.cancel(execution)
    assert :ok = Command.cancel(execution)
    assert {:ok, %Result{termination: :cancelled}} = Command.await(execution)
    assert :ok = Sandbox.close(sandbox)
  end

  @tag :tmp_dir
  test "sandbox close stops live executions and removes their handles and directory", %{
    tmp_dir: parent
  } do
    {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))
    directory = command_cwd(sandbox)

    {:ok, %Execution{} = execution} =
      Command.start(sandbox, %Spec{
        executable: erl(),
        args: ["-noshell", "-eval", "timer:sleep(infinity), halt()."],
        env: base_env(),
        inherit_env: runtime_env(),
        timeout: :infinity
      })

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
        {:ok, sandbox} = Sandbox.create(LocalNative, backend_spec(parent))
        directory = command_cwd(sandbox)

        {:ok, execution} =
          Command.start(sandbox, %Spec{
            executable: erl(),
            args: ["-noshell", "-eval", "timer:sleep(infinity), halt()."],
            env: base_env(),
            inherit_env: runtime_env(),
            timeout: :infinity
          })

        send(test_pid, {:owner_execution, execution, directory})
        receive(do: (:stop -> :ok))
      end)

    assert_receive {:owner_execution, execution, directory}, 1_000
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
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    {:ok, sandbox} = Sandbox.create(Kinda.Sandbox.CommandContractBackend, self())

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
             backend: Kinda.Sandbox.CommandContractBackend,
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

  defp backend_spec(parent), do: %BackendSpec{base_module: __MODULE__, parent_directory: parent}
  defp base_env, do: %{"LANG" => "C.UTF-8"}
  defp erl, do: System.find_executable("erl") || raise("erl executable unavailable")

  defp runtime_env do
    ["PATH", "SYSTEMROOT", "SystemRoot", "COMSPEC", "ComSpec", "PATHEXT", "TEMP", "TMP"]
  end

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
