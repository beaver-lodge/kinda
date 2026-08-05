defmodule Kinda.RootVerifier do
  @moduledoc """
  Verifies the root `kinda` repo, including bundled example surfaces.
  """

  @type command_runner :: module()

  @spec project_root(keyword()) :: Path.t()
  def project_root(opts \\ []) do
    Keyword.get(opts, :project_root, Path.expand("../..", __DIR__))
  end

  @spec verify(keyword()) :: :ok | no_return()
  def verify(opts \\ []) do
    root = project_root(opts)
    runner = Keyword.get(opts, :command_runner, Kinda.SystemCommandRunner)
    example_verifier = Keyword.get(opts, :example_verifier, Kinda.ExampleVerifier)
    env = Kinda.ExampleVerifier.command_env(opts)

    run_step(runner, "mix", ["test"], cd: root, env: env)
    run_step(runner, "mix", ["kinda.wrapper.example", "--json"], cd: root, env: env)
    example_verifier.verify(opts)
  end

  defp run_step(runner, command, args, opts) do
    case runner.cmd(command, args, Keyword.put_new(opts, :stderr_to_stdout, true)) do
      {_output, 0} ->
        :ok

      {output, status} ->
        raise """
        kinda root verification failed.
        command: #{command} #{Enum.join(args, " ")}
        status: #{status}

        #{output}
        """
    end
  end
end
