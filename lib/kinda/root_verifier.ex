defmodule Kinda.RootVerifier do
  @moduledoc """
  Verifies the root `kinda` repo, including bundled example surfaces.
  """

  @type command_runner :: Kinda.SystemCommandRunner.runner()

  @spec project_root(keyword()) :: Path.t()
  def project_root(opts \\ []) do
    Keyword.get(opts, :project_root, Path.expand("../..", __DIR__))
  end

  @spec verify(keyword()) :: :ok | no_return()
  def verify(opts \\ []) do
    root = project_root(opts)
    runner = Keyword.get(opts, :command_runner, Kinda.SystemCommandRunner)
    example_verifier = Keyword.get(opts, :example_verifier, Kinda.ExampleVerifier)

    sqlite_verifier = Keyword.get(opts, :sqlite_verifier, Kinda.ExampleVerifier)
    ecto_sqlite_verifier = Keyword.get(opts, :ecto_sqlite_verifier, Kinda.ExampleVerifier)
    duckdb_verifier = Keyword.get(opts, :duckdb_verifier, Kinda.ExampleVerifier)

    env = Kinda.ExampleVerifier.command_env(opts)

    run_step(
      runner,
      "elixir",
      ["scripts/check_test_policy.exs", "test", "packages"],
      cd: root,
      env: env
    )

    run_step(runner, "mix", ["test"], cd: root, env: env)
    run_step(runner, "mix", ["kinda.wrapper.example", "--json"], cd: root, env: env)
    verify_example(example_verifier, opts)

    verify_example(
      sqlite_verifier,
      Keyword.put(opts, :relative_path, "packages/kinda_sqlite")
    )

    verify_example(
      ecto_sqlite_verifier,
      Keyword.put(opts, :relative_path, "packages/ecto_kinda_sqlite")
    )

    verify_example(
      duckdb_verifier,
      Keyword.put(opts, :relative_path, "packages/kinda_duckdb")
    )
  end

  defp verify_example(verifier, opts) when is_function(verifier, 1), do: verifier.(opts)
  defp verify_example(verifier, opts), do: verifier.verify(opts)

  defp run_step(runner, command, args, opts) do
    Kinda.SystemCommandRunner.run!(runner, command, args, opts,
      stage: :root_verification,
      message: "kinda root verification failed"
    )

    :ok
  end
end
