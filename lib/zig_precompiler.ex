defmodule Kinda.Precompiler do
  @behaviour ElixirMake.Precompiler

  @impl true
  def current_target, do: RustlerPrecompiled.target()

  @impl true
  def all_supported_targets(_), do: ~w(
    aarch64-apple-darwin
    x86_64-unknown-linux-gnu
  )

  @impl true
  def build_native(args) do
    config = Mix.Project.config()
    app = config |> Keyword.fetch!(:app)
    version = Mix.Project.config() |> Keyword.fetch!(:version)
    {:ok, t} = current_target()
    System.put_env("KINDA_LIB_NAME", "#{app}-v#{version}-#{t}")
    ElixirMake.Compiler.compile(args)
  end

  @impl true
  def precompile(args, _target) do
    ElixirMake.Compiler.compile(args)
    :ok
  end
end
