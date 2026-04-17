defmodule Kinda.RootVerifierTest do
  use ExUnit.Case, async: true

  defmodule RunnerStub do
    def cmd(command, args, opts) do
      calls = Process.get(:root_verifier_calls, [])
      Process.put(:root_verifier_calls, calls ++ [%{command: command, args: args, opts: opts}])

      case Process.get(:root_verifier_results, %{}) do
        %{^command => %{args: ^args} = result} -> {result.output, result.status}
        _ -> {"", 0}
      end
    end
  end

  defmodule ExampleVerifierStub do
    def verify(opts) do
      Process.put(:example_verifier_opts, opts)
      :ok
    end
  end

  setup do
    Process.delete(:root_verifier_calls)
    Process.delete(:root_verifier_results)
    Process.delete(:example_verifier_opts)
    :ok
  end

  test "runs the root verification sequence" do
    root = Path.expand("..", __DIR__)

    assert :ok =
             Kinda.RootVerifier.verify(
               project_root: root,
               command_runner: RunnerStub,
               example_verifier: ExampleVerifierStub
             )

    assert [
             %{command: "mix", args: ["test"]},
             %{command: "mix", args: ["kinda.wrapper.example", "--json"]}
           ] = Process.get(:root_verifier_calls)

    assert [project_root: ^root, command_runner: RunnerStub, example_verifier: ExampleVerifierStub] =
             Process.get(:example_verifier_opts)
  end

  test "raises with command context when root verification fails" do
    root = Path.expand("..", __DIR__)

    Process.put(:root_verifier_results, %{
      "mix" => %{args: ["kinda.wrapper.example", "--json"], output: "boom", status: 1}
    })

    assert_raise RuntimeError, ~r/kinda root verification failed/, fn ->
      Kinda.RootVerifier.verify(
        project_root: root,
        command_runner: RunnerStub,
        example_verifier: ExampleVerifierStub
      )
    end
  end
end
