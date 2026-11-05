defmodule Kinda.RootVerifier do
  @moduledoc """
  Verifies the root `kinda` repo, including bundled example surfaces.
  """

  @type command_runner :: Kinda.SystemCommandRunner.runner()

  @spec project_root(keyword()) :: Path.t()
  def project_root(opts \\ []), do: Keyword.get(opts, :project_root, Path.expand("../..", __DIR__))

  @spec verify(keyword()) :: :ok | no_return()
  def verify(opts \\ []) do
    root = project_root(opts)
    runner = Keyword.get(opts, :command_runner, Kinda.SystemCommandRunner)
    env = Kinda.ExampleVerifier.command_env(opts)

    run_step(runner, "elixir", ["scripts/check_test_policy.exs", "test", "packages"], cd: root, env: env)

    run_step(runner, "mix", ["test"], cd: root, env: env)
    run_step(runner, "mix", ["kinda.wrapper.example", "--json"], cd: root, env: env)

    Enum.each(
      [
        {:example_verifier, nil},
        {:sqlite_verifier, "kinda_sqlite"},
        {:ecto_sqlite_verifier, "ecto_kinda_sqlite"},
        {:duckdb_verifier, "kinda_duckdb"}
      ],
      fn {key, package} ->
        verifier = Keyword.get(opts, key, Kinda.ExampleVerifier)
        verify_example(verifier, if(package, do: Keyword.put(opts, :relative_path, "packages/#{package}"), else: opts))
      end
    )

    :ok
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
