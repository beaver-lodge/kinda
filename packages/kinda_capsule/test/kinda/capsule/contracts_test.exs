defmodule Kinda.Capsule.ContractsTest do
  use ExUnit.Case, async: true

  alias Kinda.Capsule
  alias Kinda.Capsule.{Error, Execution, Handle, Observation, Score, Spec}
  alias Kinda.Capsule.SandboxSpec

  defmodule Task do
    @behaviour Kinda.Capsule.Task

    @impl true
    def reset(_context, seed, _options), do: {:ok, %{seed: seed}, %Observation{value: seed}}

    @impl true
    def observe(_context, state), do: {:ok, %Observation{value: state.seed}}

    @impl true
    def close(_context, _state), do: :ok
  end

  defmodule Verifier do
    @behaviour Kinda.Capsule.Verifier

    @impl true
    def grade(_verification, _options), do: {:ok, %Score{value: 1}}
  end

  test "public handles contain only an opaque ref" do
    ref = make_ref()
    assert %Handle{ref: ^ref} = Handle.new(ref)
    assert %Execution{ref: ^ref} = Execution.new(ref)
    assert Map.keys(Map.from_struct(Handle.new(ref))) == [:ref]
    assert Map.keys(Map.from_struct(Execution.new(ref))) == [:ref]
  end

  test "validates the complete static spec" do
    spec = valid_spec()
    assert :ok = Spec.validate(spec)
  end

  test "rejects missing callbacks and invalid limits" do
    assert {:error, %Error{phase: :create, reason: :invalid_spec}} =
             valid_spec()
             |> Map.put(:task, Capsule)
             |> Spec.validate()

    assert {:error, %Error{phase: :create, reason: :invalid_spec}} =
             valid_spec()
             |> Map.put(:max_steps, 0)
             |> Spec.validate()
  end

  test "score validation accepts only numeric components and map metadata" do
    assert Score.valid?(%Score{value: 1.0, components: %{quality: 0.5}})
    refute Score.valid?(%Score{value: 1, components: %{quality: :high}})
    refute Score.valid?(%Score{value: 1, metadata: []})
  end

  test "error phases cover every public operation family" do
    assert Error.phases() == [:create, :reset, :execute, :observe, :grade, :trace, :close]
  end

  defp valid_spec do
    %Spec{
      task: Task,
      task_version: "task@1",
      verifier: Verifier,
      verifier_version: "verifier@1",
      sandbox: %SandboxSpec{
        backend: Kinda.Sandbox.Backend.LocalProcess,
        backend_spec: %Kinda.Sandbox.Backend.LocalProcess.Spec{}
      }
    }
  end
end
