defmodule Kinda.Capsule.CommandTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule
  alias Kinda.Capsule.Action.Command
  alias Kinda.Capsule.{Artifact, Error, Observation, SandboxSpec, Score, Spec}
  alias Kinda.Sandbox

  @process_start_timeout 5_000

  defmodule Task do
    @behaviour Kinda.Capsule.Task

    @impl true
    def reset(_context, seed, _options), do: {:ok, seed, %Observation{value: seed}}

    @impl true
    def observe(_context, seed), do: {:ok, %Observation{value: seed}}

    @impl true
    def close(_context, _state), do: :ok
  end

  defmodule Verifier do
    @behaviour Kinda.Capsule.Verifier

    @impl true
    def grade(_verification, _options), do: {:ok, %Score{value: 1}}
  end

  @tag :tmp_dir
  test "commands produce ordered safe trace projections", %{tmp_dir: parent} do
    {:ok, capsule} = Capsule.create(spec(parent, max_steps: 2))
    {:ok, _observation} = Capsule.reset(capsule, seed: 7)
    secret = "capsule-secret-#{System.unique_integer([:positive])}"

    action =
      command(output_command(),
        env: %{"CAPSULE_SECRET" => secret},
        stdin: secret,
        metadata: %{label: "first"}
      )

    assert {:ok, %{termination: {:exit, 0}, stdout: "first", stderr: "err"}} =
             Capsule.execute(capsule, action)

    assert {:ok, %{termination: {:exit, 0}}} =
             Capsule.execute(capsule, command(success_command()))

    assert {:error, %Error{reason: :step_limit}} =
             Capsule.start(capsule, command(success_command()))

    assert {:ok, trace} = Capsule.trace(capsule)
    assert Enum.map(trace.steps, & &1.sequence) == [0, 1]
    assert [first | _rest] = trace.steps
    assert first.action.env_keys == ["CAPSULE_SECRET"]
    assert first.action.stdin_bytes == byte_size(secret)
    assert first.metadata == %{label: "first"}
    refute inspect(trace) =~ secret
    assert :ok = Capsule.close(capsule)
  end

  @tag :tmp_dir
  test "artifacts project stable evidence references onto their producing step", %{
    tmp_dir: parent
  } do
    {:ok, capsule} = Capsule.create(spec(parent))
    {:ok, _observation} = Capsule.reset(capsule, seed: 7)
    {:ok, _result} = Capsule.execute(capsule, command(success_command()))

    artifact = %Artifact{
      id: "evidence-id",
      name: "trace.json",
      kind: :trace,
      path: "artifacts/trace.json",
      sha256: String.duplicate("0", 64),
      media_type: "application/json",
      produced_by: %{step: 0}
    }

    assert :ok = Capsule.attach_artifact(capsule, artifact)

    assert {:ok, %{steps: [%{evidence: [%{artifact: "evidence-id"}]}]}} =
             Capsule.trace(capsule)

    assert :ok = Capsule.close(capsule)
  end

  @tag :tmp_dir
  test "only one action runs and cancellation is idempotent", %{tmp_dir: parent} do
    {:ok, capsule} = Capsule.create(spec(parent))
    {:ok, _observation} = Capsule.reset(capsule, seed: 1)
    {:ok, execution} = Capsule.start(capsule, command(sleep_command()))

    assert {:error, %Error{reason: :busy}} = Capsule.start(capsule, command(success_command()))
    assert {:error, %Error{reason: :busy}} = Capsule.observe(capsule)
    assert :ok = Capsule.cancel(execution)
    assert :ok = Capsule.cancel(execution)
    assert {:ok, %{termination: :cancelled}} = Capsule.await(execution)

    assert_eventually(fn ->
      match?({:ok, %{steps: [%{termination: :cancelled}]}}, Capsule.trace(capsule))
    end)

    assert :ok = Capsule.close(capsule)
  end

  @tag :tmp_dir
  test "reset clears trace and disconnects old executions", %{tmp_dir: parent} do
    {:ok, capsule} = Capsule.create(spec(parent))
    {:ok, _observation} = Capsule.reset(capsule, seed: :first)
    {:ok, execution} = Capsule.start(capsule, command(success_command()))
    assert {:ok, _result} = Capsule.await(execution)
    assert_eventually(fn -> match?({:ok, %{steps: [_step]}}, Capsule.trace(capsule)) end)

    {:ok, _observation} = Capsule.reset(capsule, seed: :second)
    assert {:ok, %{seed: :second, steps: []}} = Capsule.trace(capsule)
    assert {:error, %Error{reason: :disconnected}} = Capsule.await(execution)
    assert :ok = Capsule.cancel(execution)
    assert :ok = Capsule.close(capsule)
  end

  @tag :tmp_dir
  test "owner exit cancels an active process before it can write", %{tmp_dir: parent} do
    test = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        {:ok, capsule} = Capsule.create(spec(parent))
        {:ok, _observation} = Capsule.reset(capsule, seed: 1)
        {:ok, execution} = Capsule.start(capsule, late_write_command())
        send(test, {:active_execution, execution})
        receive(do: (:stop -> :ok))
      end)

    assert_receive {:active_execution, execution}, @process_start_timeout
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}

    assert_eventually(fn ->
      match?({:error, %Error{reason: :disconnected}}, Capsule.await(execution))
    end)

    Process.sleep(400)
    assert Path.wildcard(Path.join([parent, "**", "late"])) == []
  end

  defp spec(parent, options \\ []) do
    %Spec{
      task: Task,
      task_version: "task@1",
      verifier: Verifier,
      verifier_version: "verifier@1",
      sandbox: %SandboxSpec{
        backend: Kinda.Sandbox.Backend.LocalProcess,
        backend_spec: %Kinda.Sandbox.Backend.LocalProcess.Spec{parent_directory: parent}
      },
      max_steps: Keyword.get(options, :max_steps, 10)
    }
  end

  defp command({executable, args}, options \\ []) do
    metadata = Keyword.get(options, :metadata, %{})

    %Command{
      spec: %Sandbox.Command.Spec{
        executable: executable,
        args: args,
        env: Keyword.get(options, :env, %{}),
        inherit_env: runtime_env(),
        stdin: Keyword.get(options, :stdin, :closed)
      },
      metadata: metadata
    }
  end

  defp output_command do
    {erl(),
     [
       "-noshell",
       "-eval",
       ~S|io:put_chars(standard_io, "first"), io:put_chars(standard_error, "err"), halt().|
     ]}
  end

  defp success_command, do: {erl(), ["-noshell", "-eval", "halt()."]}
  defp sleep_command, do: {erl(), ["-noshell", "-eval", "timer:sleep(infinity), halt()."]}

  defp erl, do: System.find_executable("erl") || raise("erl executable unavailable")

  defp runtime_env do
    ["PATH", "SYSTEMROOT", "SystemRoot", "COMSPEC", "ComSpec", "PATHEXT", "TEMP", "TMP"]
  end

  defp late_write_command do
    %Command{
      spec: %Sandbox.Command.Spec{
        executable: erl(),
        args: [
          "-noshell",
          "-eval",
          ~S|timer:sleep(250), file:write_file("late", <<"leaked">>), halt().|
        ],
        env: %{"LANG" => "C.UTF-8"},
        inherit_env: runtime_env(),
        timeout: :infinity
      }
    }
  end

  defp assert_eventually(assertion, attempts \\ 100)
  defp assert_eventually(assertion, 0), do: assert(assertion.())

  defp assert_eventually(assertion, attempts) do
    if assertion.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end
end
