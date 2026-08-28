defmodule Kinda.Capsule.LifecycleTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule
  alias Kinda.Capsule.{Error, Observation, SandboxSpec, Score, Spec}
  alias Kinda.Sandbox

  defmodule FakeBackend do
    @behaviour Kinda.Sandbox.Backend

    @impl true
    def capabilities, do: %{command: __MODULE__.Command}

    @impl true
    def create(%{test: test, id: id} = spec, _options) do
      send(test, {:sandbox_created, id, self()})
      {:ok, %{test: test, id: id, close_mode: Map.get(spec, :close_mode, :ok)}}
    end

    @impl true
    def close(%{test: test, id: id, close_mode: close_mode}) do
      send(test, {:sandbox_closed, id})

      case close_mode do
        :ok -> :ok
        :error -> {:error, Sandbox.Error.exception(reason: :backend_failure)}
      end
    end

    defmodule Command do
      @behaviour Kinda.Sandbox.Capability.Command

      @impl true
      def stream(_handle, _spec), do: {:error, :not_used}
    end
  end

  defmodule NoCommandBackend do
    @behaviour Kinda.Sandbox.Backend

    @impl true
    def capabilities, do: %{}

    @impl true
    def create(%{test: test}, _options), do: {:ok, test}

    @impl true
    def close(test) do
      send(test, :unsupported_sandbox_closed)
      :ok
    end
  end

  defmodule Task do
    @behaviour Kinda.Capsule.Task

    @impl true
    def reset(context, seed, options) do
      test = Keyword.fetch!(options, :test)
      mode = Keyword.get(options, :mode, :ok)
      observe_mode = Keyword.get(options, :observe_mode, :ok)
      close_mode = Keyword.get(options, :close_mode, :ok)
      send(test, {:task_reset, seed, self(), context.sandbox})

      case mode do
        :ok ->
          state = %{test: test, seed: seed, observe_mode: observe_mode, close_mode: close_mode}
          {:ok, state, %Observation{value: seed}}

        :error ->
          {:error, :reset_failed}

        :raise ->
          raise "reset failed"

        :throw ->
          throw(:reset_failed)

        :exit ->
          exit(:reset_failed)

        :invalid ->
          :invalid
      end
    end

    @impl true
    def observe(_context, %{test: test, seed: seed, observe_mode: mode} = state) do
      send(test, {:task_observe, self()})

      case mode do
        :ok -> {:ok, %Observation{value: seed}}
        :error -> {:error, :observe_failed}
        :raise -> raise "observe failed"
        :invalid -> {:ok, state}
      end
    end

    @impl true
    def close(_context, %{test: test, seed: seed, close_mode: close_mode}) do
      send(test, {:task_closed, seed})

      case close_mode do
        :ok -> :ok
        :error -> {:error, :close_failed}
      end
    end
  end

  defmodule Verifier do
    @behaviour Kinda.Capsule.Verifier

    @impl true
    def grade(_verification, _options), do: {:ok, %Score{value: 1}}
  end

  defmodule LocalProcessTask do
    @behaviour Kinda.Capsule.Task

    @impl true
    def reset(context, _seed, _options) do
      spec = %Sandbox.Command.Spec{
        executable: System.find_executable("erl") || raise("erl executable unavailable"),
        args: ["-noshell", "-eval", "{ok, Cwd} = file:get_cwd(), io:put_chars(Cwd), halt()."],
        env: %{"LANG" => "C.UTF-8"},
        inherit_env: runtime_env()
      }

      {:ok, result} = Sandbox.Command.run(context.sandbox, spec)
      directory = String.trim(result.stdout)
      {:ok, %{directory: directory}, %Observation{value: directory}}
    end

    @impl true
    def observe(_context, state), do: {:ok, %Observation{value: state.directory}}

    @impl true
    def close(_context, _state), do: :ok

    defp runtime_env do
      ["PATH", "SYSTEMROOT", "SystemRoot", "COMSPEC", "ComSpec", "PATHEXT", "TEMP", "TMP"]
    end
  end

  test "reset runs callbacks inside the Capsule server and close is idempotent" do
    {:ok, capsule} = Capsule.create(spec(test: self(), id: :first))
    {:ok, %Observation{value: 42}} = Capsule.reset(capsule, seed: 42)

    assert_receive {:sandbox_created, :first, sandbox_server}
    assert_receive {:task_reset, 42, capsule_server, %Sandbox.Handle{}}
    refute sandbox_server == capsule_server
    refute capsule_server == self()

    assert :ok = Capsule.close(capsule)
    assert_receive {:task_closed, 42}
    assert_receive {:sandbox_closed, :first}
    assert :ok = Capsule.close(capsule)
    refute_receive {:sandbox_closed, :first}
  end

  test "every successful reset creates a new addressable episode" do
    {:ok, capsule} = Capsule.create(spec(test: self(), id: :identity))

    {:ok, _observation} = Capsule.reset(capsule, seed: 1)
    {:ok, first} = Capsule.episode(capsule)
    {:ok, first_trace} = Capsule.trace(capsule)
    {:ok, _observation} = Capsule.reset(capsule, seed: 2)
    {:ok, second} = Capsule.episode(capsule)

    assert first.capsule_id == second.capsule_id
    refute first.episode_id == second.episode_id
    assert first_trace.episode_id == first.episode_id
    assert first.fixture_digest == "unspecified"
    assert first.verifier_source_digest == "unspecified"
    assert first.verifier_executable_digest == "unspecified"

    assert :ok = Capsule.close(capsule)
  end

  test "owner exit closes task and Sandbox" do
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        {:ok, capsule} = Capsule.create(spec(test: parent, id: :owner))
        {:ok, _observation} = Capsule.reset(capsule, seed: 7)
        send(parent, {:capsule, capsule})
        receive(do: (:stop -> :ok))
      end)

    assert_receive {:capsule, capsule}
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    assert_receive {:task_closed, 7}
    assert_receive {:sandbox_closed, :owner}
    assert {:error, %Error{reason: :disconnected}} = Capsule.observe(capsule)
  end

  @tag :tmp_dir
  test "reset replaces the real LocalProcess directory", %{tmp_dir: parent} do
    {:ok, capsule} =
      Capsule.create(
        spec(
          task: LocalProcessTask,
          backend: Kinda.Sandbox.Backend.LocalProcess,
          backend_spec: %Kinda.Sandbox.Backend.LocalProcess.Spec{parent_directory: parent}
        )
      )

    {:ok, %Observation{value: first}} = Capsule.reset(capsule, seed: 1)
    assert File.dir?(first)
    {:ok, %Observation{value: second}} = Capsule.reset(capsule, seed: 2)
    refute first == second
    refute File.exists?(first)
    assert File.dir?(second)
    assert :ok = Capsule.close(capsule)
    refute File.exists?(second)
  end

  test "failed reset closes a created Sandbox and permits retry" do
    failing = spec(test: self(), id: :failed, mode: :error)
    {:ok, capsule} = Capsule.create(failing)

    assert {:error, %Error{phase: :reset, reason: :task_error}} =
             Capsule.reset(capsule, seed: 1)

    assert_receive {:sandbox_closed, :failed}
    assert {:error, %Error{reason: :not_reset}} = Capsule.observe(capsule)
    assert :ok = Capsule.close(capsule)
  end

  test "backend without command capability fails reset and is closed" do
    {:ok, capsule} =
      Capsule.create(
        spec(
          test: self(),
          backend: NoCommandBackend,
          backend_spec: %{test: self()}
        )
      )

    assert {:error, %Error{reason: :unsupported_capability}} =
             Capsule.reset(capsule, seed: 1)

    assert_receive :unsupported_sandbox_closed
    assert {:error, %Error{reason: :not_reset}} = Capsule.observe(capsule)
  end

  test "declared observe errors preserve the current episode" do
    {:ok, capsule} =
      Capsule.create(spec(test: self(), id: :observe, observe_mode: :error))

    {:ok, _observation} = Capsule.reset(capsule, seed: 9)

    assert {:error, %Error{reason: :task_error}} = Capsule.observe(capsule)
    assert_receive {:task_observe, _server}
    assert {:error, %Error{reason: :task_error}} = Capsule.observe(capsule)
    assert_receive {:task_observe, _server}
    assert :ok = Capsule.close(capsule)
  end

  test "old task cleanup failure prevents replacement but still closes Sandbox" do
    {:ok, capsule} =
      Capsule.create(spec(test: self(), id: :task_cleanup, close_mode: :error))

    {:ok, _observation} = Capsule.reset(capsule, seed: 1)
    assert_receive {:sandbox_created, :task_cleanup, _server}

    assert {:error, %Error{phase: :reset, reason: :task_cleanup_failed}} =
             Capsule.reset(capsule, seed: 2)

    assert_receive {:task_closed, 1}
    assert_receive {:sandbox_closed, :task_cleanup}
    refute_receive {:sandbox_created, :task_cleanup, _server}
    assert {:error, %Error{reason: :not_reset}} = Capsule.observe(capsule)
    assert :ok = Capsule.close(capsule)
  end

  test "old Sandbox cleanup failure prevents replacement after task cleanup" do
    backend_spec = %{test: self(), id: :sandbox_cleanup, close_mode: :error}
    {:ok, capsule} = Capsule.create(spec(test: self(), backend_spec: backend_spec))
    {:ok, _observation} = Capsule.reset(capsule, seed: 1)
    assert_receive {:sandbox_created, :sandbox_cleanup, _server}

    assert {:error, %Error{phase: :reset, reason: :sandbox_failure}} =
             Capsule.reset(capsule, seed: 2)

    assert_receive {:task_closed, 1}
    assert_receive {:sandbox_closed, :sandbox_cleanup}
    refute_receive {:sandbox_created, :sandbox_cleanup, _server}
    assert {:error, %Error{reason: :not_reset}} = Capsule.trace(capsule)
    assert :ok = Capsule.close(capsule)
  end

  test "a failing first close is complete and later close is idempotent" do
    {:ok, capsule} = Capsule.create(spec(test: self(), id: :close_error, close_mode: :error))
    {:ok, _observation} = Capsule.reset(capsule, seed: 5)

    assert {:error, %Error{phase: :close, reason: :task_cleanup_failed}} =
             Capsule.close(capsule)

    assert_receive {:task_closed, 5}
    assert_receive {:sandbox_closed, :close_error}
    assert :ok = Capsule.close(capsule)
    refute_receive {:task_closed, 5}
    refute_receive {:sandbox_closed, :close_error}
  end

  test "reset catches invalid returns, raises, throws, and exits" do
    Enum.each([:invalid, :raise, :throw, :exit], fn mode ->
      {:ok, capsule} = Capsule.create(spec(test: self(), id: mode, mode: mode))
      assert {:error, %Error{phase: :reset}} = Capsule.reset(capsule, seed: mode)
      assert_receive {:sandbox_closed, ^mode}
      assert {:error, %Error{reason: :not_reset}} = Capsule.trace(capsule)
      assert :ok = Capsule.close(capsule)
    end)
  end

  defp spec(options) do
    test = Keyword.get(options, :test, self())
    backend = Keyword.get(options, :backend, FakeBackend)

    backend_spec =
      Keyword.get(options, :backend_spec, %{
        test: test,
        id: options[:id],
        close_mode: Keyword.get(options, :backend_close_mode, :ok)
      })

    %Spec{
      task: Keyword.get(options, :task, Task),
      task_version: "task@1",
      task_options: [
        test: test,
        mode: Keyword.get(options, :mode, :ok),
        observe_mode: Keyword.get(options, :observe_mode, :ok),
        close_mode: Keyword.get(options, :close_mode, :ok)
      ],
      verifier: Verifier,
      verifier_version: "verifier@1",
      sandbox: %SandboxSpec{backend: backend, backend_spec: backend_spec}
    }
  end
end
