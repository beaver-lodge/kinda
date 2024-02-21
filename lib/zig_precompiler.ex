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
    ElixirMake.Compiler.compile(args)
  end

  @impl true
  def precompile(args, _target) do
    build_native(args)
    :ok
  end
end
