defmodule Kinda.ExampleVerifierTest do
  use ExUnit.Case, async: true

  test "default example_root resolves to the bundled kinda_example app" do
    assert Kinda.ExampleVerifier.example_root()
           |> Path.basename() == "kinda_example"
  end

  test "syncs deps when lockfile and deps directory are present" do
    root = make_tmp_dir()
    File.write!(Path.join(root, "mix.lock"), "%{}")
    File.mkdir_p!(Path.join(root, "deps"))
    test_process = self()

    runner = fn command, args, opts ->
      send(test_process, {:command, command, args, opts})
      {"", 0}
    end

    assert :ok =
             Kinda.ExampleVerifier.verify(
               project_root: root,
               relative_path: ".",
               command_runner: runner
             )

    assert_received {:command, "mix", ["deps.get"], deps_opts}
    assert_received {:command, "mix", ["test", "--force"], test_opts}
    assert deps_opts[:stderr_to_stdout]
    assert test_opts[:stderr_to_stdout]
  end

  test "runs deps.get before tests when example deps are missing" do
    root = make_tmp_dir()
    test_process = self()

    runner = fn command, args, opts ->
      send(test_process, {:command, command, args, opts})
      {"", 0}
    end

    assert :ok =
             Kinda.ExampleVerifier.verify(
               project_root: root,
               relative_path: ".",
               command_runner: runner
             )

    assert_received {:command, "mix", ["deps.get"], _opts}
    assert_received {:command, "mix", ["test", "--force"], _opts}
  end

  test "injects a preferred zig path into command env when configured" do
    env =
      Kinda.ExampleVerifier.command_env(zig_bin: "/tmp/zig-0.15/bin/zig")

    assert [{"PATH", path}] = env
    assert String.starts_with?(path, "/tmp/zig-0.15/bin:")
  end

  test "raises with command context when nested example verification fails" do
    root = make_tmp_dir()
    File.write!(Path.join(root, "mix.lock"), "%{}")
    File.mkdir_p!(Path.join(root, "deps"))

    runner = fn
      "mix", ["test", "--force"], _opts -> {"boom", 1}
      _command, _args, _opts -> {"", 0}
    end

    error =
      assert_raise Kinda.CommandError, fn ->
        Kinda.ExampleVerifier.verify(
          project_root: root,
          relative_path: ".",
          command_runner: runner
        )
      end

    assert error.stage == :example_verification
    assert error.command == "mix"
    assert error.args == ["test", "--force"]
    assert error.cwd == root
    assert error.status == 1
    assert error.output == "boom"
    assert Exception.message(error) =~ "kinda_example verification failed"
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
