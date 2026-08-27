defmodule Kinda.Capsule.GradingTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule
  alias Kinda.Capsule.Action.Command
  alias Kinda.Capsule.{Error, Observation, SandboxSpec, Score, Spec, Verification}
  alias Kinda.Sandbox

  defmodule Task do
    @behaviour Kinda.Capsule.Task

    @impl true
    def reset(_context, seed, options) do
      counter = Keyword.fetch!(options, :counter)
      Agent.update(counter, fn _value -> 0 end)
      {:ok, counter, %Observation{value: {:reset, seed}}}
    end

    @impl true
    def observe(_context, counter) do
      value = Agent.get_and_update(counter, fn value -> {value + 1, value + 1} end)
      {:ok, %Observation{value: value}}
    end

    @impl true
    def close(_context, _counter), do: :ok
  end

  defmodule InvalidObserveTask do
    @behaviour Kinda.Capsule.Task

    @impl true
    def reset(_context, _seed, _options), do: {:ok, :state, %Observation{value: :reset}}

    @impl true
    def observe(_context, _state), do: :invalid

    @impl true
    def close(_context, _state), do: :ok
  end

  defmodule Verifier do
    @behaviour Kinda.Capsule.Verifier

    @impl true
    def grade(%Verification{} = verification, options) do
      send(Keyword.fetch!(options, :test), {:verification, verification})

      case Keyword.get(options, :mode, :ok) do
        :ok -> {:ok, %Score{value: verification.observation.value}}
        :error -> {:error, :rejected}
        :invalid -> {:ok, %Score{value: :invalid}}
        :raise -> raise "verifier failed"
      end
    end
  end

  @tag :tmp_dir
  test "grade takes a fresh observation and stores a valid score", %{tmp_dir: parent} do
    {:ok, counter} = start_supervised({Agent, fn -> -1 end})
    {:ok, capsule} = Capsule.create(spec(parent, counter))
    {:ok, _observation} = Capsule.reset(capsule, seed: "seed")

    assert {:ok, %Score{value: 1} = score} = Capsule.grade(capsule)
    assert_receive {:verification, verification}
    assert verification.observation.value == 1
    refute inspect(verification) =~ "Kinda.Sandbox.Handle"
    assert {:ok, %{score: ^score}} = Capsule.trace(capsule)
    assert :ok = Capsule.close(capsule)
  end

  @tag :tmp_dir
  test "verifier failures preserve the episode", %{tmp_dir: parent} do
    {:ok, counter} = start_supervised({Agent, fn -> -1 end})
    {:ok, capsule} = Capsule.create(spec(parent, counter, verifier_mode: :error))
    {:ok, _observation} = Capsule.reset(capsule, seed: 1)

    assert {:error, %Error{phase: :grade, reason: :verifier_error}} = Capsule.grade(capsule)
    assert_receive {:verification, _verification}
    assert {:ok, %Observation{value: 2}} = Capsule.observe(capsule)
    assert {:ok, %{score: nil}} = Capsule.trace(capsule)
    assert :ok = Capsule.close(capsule)
  end

  @tag :tmp_dir
  test "an invalid task observation tears down the episode", %{tmp_dir: parent} do
    {:ok, counter} = start_supervised({Agent, fn -> -1 end})
    {:ok, capsule} = Capsule.create(spec(parent, counter, task: InvalidObserveTask))
    {:ok, _observation} = Capsule.reset(capsule, seed: 1)

    assert {:error, %Error{phase: :grade, reason: :invalid_callback_return}} =
             Capsule.grade(capsule)

    assert {:error, %Error{reason: :not_reset}} = Capsule.trace(capsule)
    assert :ok = Capsule.close(capsule)
  end

  @tag :tmp_dir
  test "telemetry contains lifecycle facts but no episode payloads", %{tmp_dir: parent} do
    handler_id = {__MODULE__, self()}
    operations = [:create, :reset, :execute, :observe, :grade, :trace, :close]
    events = Enum.map(operations, &[:kinda, :capsule, &1])

    :ok = :telemetry.attach_many(handler_id, events, &__MODULE__.handle_telemetry/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)

    secret = "telemetry-secret-#{System.unique_integer([:positive])}"
    {:ok, counter} = start_supervised({Agent, fn -> -1 end})
    {:ok, capsule} = Capsule.create(spec(parent, counter))
    {:ok, _observation} = Capsule.reset(capsule, seed: secret)

    action = %Command{
      spec: %Sandbox.Command.Spec{
        executable: executable(),
        args: success_args(),
        env: %{"CAPSULE_SECRET" => secret},
        stdin: secret
      },
      metadata: %{secret: secret}
    }

    assert {:ok, _result} = Capsule.execute(capsule, action)
    assert {:ok, _observation} = Capsule.observe(capsule)
    assert {:ok, _score} = Capsule.grade(capsule)
    assert {:ok, _trace} = Capsule.trace(capsule)
    assert :ok = Capsule.close(capsule)

    telemetry = collect_telemetry([])

    assert Enum.all?(operations, fn operation ->
             Enum.any?(telemetry, fn {event, _measurements, _metadata} ->
               event == [:kinda, :capsule, operation]
             end)
           end)

    refute inspect(telemetry) =~ secret
  end

  def handle_telemetry(event, measurements, metadata, test) do
    send(test, {:capsule_telemetry, event, measurements, metadata})
  end

  defp collect_telemetry(events) do
    receive do
      {:capsule_telemetry, event, measurements, metadata} ->
        collect_telemetry([{event, measurements, metadata} | events])
    after
      25 -> events
    end
  end

  defp spec(parent, counter, options \\ []) do
    %Spec{
      task: Keyword.get(options, :task, Task),
      task_version: "task@1",
      task_options: [counter: counter],
      verifier: Verifier,
      verifier_version: "verifier@1",
      verifier_options: [test: self(), mode: Keyword.get(options, :verifier_mode, :ok)],
      sandbox: %SandboxSpec{
        backend: Kinda.Sandbox.Backend.LocalProcess,
        backend_spec: %Kinda.Sandbox.Backend.LocalProcess.Spec{parent_directory: parent}
      }
    }
  end

  if :os.type() == {:win32, :nt} do
    defp executable, do: "cmd.exe"
    defp success_args, do: ["/d", "/s", "/c", "exit", "0"]
  else
    defp executable, do: "/bin/sh"
    defp success_args, do: ["-c", "exit 0"]
  end
end
