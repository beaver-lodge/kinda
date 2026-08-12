defmodule Kinda.ExampleVerifier do
  @moduledoc """
  Verifies the bundled `kinda_example` application from the root repo.
  """

  @type command_runner :: Kinda.SystemCommandRunner.runner()

  @spec example_root(keyword()) :: Path.t()
  def example_root(opts \\ []) do
    project_root = Keyword.get(opts, :project_root, Path.expand("../..", __DIR__))
    relative_path = Keyword.get(opts, :relative_path, "packages/kinda_example")

    Path.expand(relative_path, project_root)
  end

  @spec verify(keyword()) :: :ok | no_return()
  def verify(opts \\ []) do
    root = example_root(opts)
    runner = Keyword.get(opts, :command_runner, Kinda.SystemCommandRunner)
    env = command_env(opts)

    sync_deps(root, runner, env)
    run_step(runner, "mix", ["test", "--force"], cd: root, env: env)
  end

  @spec sync_deps(Path.t(), command_runner(), keyword()) :: :ok | no_return()
  def sync_deps(root, runner, env) do
    run_step(runner, "mix", ["deps.get"], cd: root, env: env)
  end

  @spec command_env(keyword()) :: [{String.t(), String.t()}]
  def command_env(opts \\ []) do
    case zig_bin(opts) do
      nil ->
        []

      zig ->
        current_path = System.get_env("PATH", "")
        zig_dir = Path.dirname(zig)
        [{"PATH", zig_dir <> ":" <> current_path}]
    end
  end

  defp zig_bin(opts) do
    Keyword.get(opts, :zig_bin) ||
      System.get_env("KINDA_ZIG_BIN") ||
      detect_zig_016()
  end

  defp detect_zig_016 do
    candidate = "/opt/homebrew/opt/zig/bin/zig"

    if File.exists?(candidate), do: candidate, else: nil
  end

  defp run_step(runner, command, args, opts) do
    Kinda.SystemCommandRunner.run!(runner, command, args, opts,
      stage: :example_verification,
      message: "kinda_example verification failed"
    )

    :ok
  end
end
