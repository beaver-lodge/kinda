defmodule Kinda.RootVerifierTest do
  use ExUnit.Case, async: true

  test "runs the root verification sequence" do
    root = Path.expand("..", __DIR__)
    test_process = self()

    runner = fn command, args, opts ->
      send(test_process, {:command, command, args, opts})
      {"", 0}
    end

    example_verifier = fn opts ->
      send(test_process, {:example_verifier, opts})
      :ok
    end

    sqlite_verifier = fn opts ->
      send(test_process, {:sqlite_verifier, opts})
      :ok
    end

    ecto_sqlite_verifier = fn opts ->
      send(test_process, {:ecto_sqlite_verifier, opts})
      :ok
    end

    assert :ok =
             Kinda.RootVerifier.verify(
               project_root: root,
               command_runner: runner,
               example_verifier: example_verifier,
               sqlite_verifier: sqlite_verifier,
               ecto_sqlite_verifier: ecto_sqlite_verifier
             )

    assert_received {:command, "mix", ["test"], test_opts}
    assert_received {:command, "mix", ["kinda.wrapper.example", "--json"], wrapper_opts}
    assert test_opts[:stderr_to_stdout]
    assert wrapper_opts[:stderr_to_stdout]

    assert_received {:example_verifier,
                     [
                       project_root: ^root,
                       command_runner: ^runner,
                       example_verifier: ^example_verifier,
                       sqlite_verifier: ^sqlite_verifier,
                       ecto_sqlite_verifier: ^ecto_sqlite_verifier
                     ]}

    assert_received {:sqlite_verifier, sqlite_opts}
    assert sqlite_opts[:project_root] == root
    assert sqlite_opts[:command_runner] == runner
    assert sqlite_opts[:relative_path] == "packages/kinda_sqlite"

    assert_received {:ecto_sqlite_verifier, ecto_sqlite_opts}
    assert ecto_sqlite_opts[:project_root] == root
    assert ecto_sqlite_opts[:command_runner] == runner
    assert ecto_sqlite_opts[:relative_path] == "packages/ecto_kinda_sqlite"
  end

  test "raises with command context when root verification fails" do
    root = Path.expand("..", __DIR__)

    runner = fn
      "mix", ["kinda.wrapper.example", "--json"], _opts -> {"boom", 1}
      _command, _args, _opts -> {"", 0}
    end

    example_verifier = fn _opts -> :ok end
    sqlite_verifier = fn _opts -> :ok end
    ecto_sqlite_verifier = fn _opts -> :ok end

    error =
      assert_raise Kinda.CommandError, fn ->
        Kinda.RootVerifier.verify(
          project_root: root,
          command_runner: runner,
          example_verifier: example_verifier,
          sqlite_verifier: sqlite_verifier,
          ecto_sqlite_verifier: ecto_sqlite_verifier
        )
      end

    assert error.stage == :root_verification
    assert error.command == "mix"
    assert error.args == ["kinda.wrapper.example", "--json"]
    assert error.cwd == root
    assert error.status == 1
    assert error.output == "boom"
    assert Exception.message(error) =~ "kinda root verification failed"
  end
end
