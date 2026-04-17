defmodule Kinda.ExampleVerifierTest do
  use ExUnit.Case, async: true

  defmodule RunnerStub do
    def cmd(command, args, opts) do
      calls = Process.get(:example_verifier_calls, [])
      Process.put(:example_verifier_calls, calls ++ [%{command: command, args: args, opts: opts}])

      case Process.get(:example_verifier_results, %{}) do
        %{^command => %{args: ^args} = result} -> {result.output, result.status}
        _ -> {"", 0}
      end
    end
  end

  setup do
    Process.delete(:example_verifier_calls)
    Process.delete(:example_verifier_results)
    :ok
  end

  test "default example_root resolves to the bundled kinda_example app" do
    assert Kinda.ExampleVerifier.example_root()
           |> Path.basename() == "kinda_example"
  end

  test "skips deps sync when lockfile and deps directory are present" do
    root = make_tmp_dir()
    File.write!(Path.join(root, "mix.lock"), "%{}")
    File.mkdir_p!(Path.join(root, "deps"))

    assert :ok =
             Kinda.ExampleVerifier.verify(
               project_root: root,
               relative_path: ".",
               command_runner: RunnerStub
             )

    assert [
             %{command: "mix", args: ["test", "--force"]}
           ] = Process.get(:example_verifier_calls)
  end

  test "runs deps.get before tests when example deps are missing" do
    root = make_tmp_dir()

    assert :ok =
             Kinda.ExampleVerifier.verify(
               project_root: root,
               relative_path: ".",
               command_runner: RunnerStub
             )

    assert [
             %{command: "mix", args: ["deps.get"]},
             %{command: "mix", args: ["test", "--force"]}
           ] = Process.get(:example_verifier_calls)
  end

  test "injects a preferred zig path into command env when configured" do
    env =
      Kinda.ExampleVerifier.command_env(
        zig_bin: "/tmp/zig-0.15/bin/zig"
      )

    assert [{"PATH", path}] = env
    assert String.starts_with?(path, "/tmp/zig-0.15/bin:")
  end

  test "raises with command context when nested example verification fails" do
    root = make_tmp_dir()
    File.write!(Path.join(root, "mix.lock"), "%{}")
    File.mkdir_p!(Path.join(root, "deps"))

    Process.put(:example_verifier_results, %{
      "mix" => %{args: ["test", "--force"], output: "boom", status: 1}
    })

    assert_raise RuntimeError, ~r/kinda_example verification failed/, fn ->
      Kinda.ExampleVerifier.verify(
        project_root: root,
        relative_path: ".",
        command_runner: RunnerStub
      )
    end
  end

  defp make_tmp_dir do
    root =
      Path.join(
        System.tmp_dir!(),
        "kinda-example-verifier-#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
