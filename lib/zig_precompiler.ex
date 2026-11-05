defmodule Kinda.Precompiler do
  @moduledoc """
  The `ElixirMake.Precompiler` implementation for Kinda-built NIFs.

  Resolves the current target, supported targets and artifact metadata so
  consumers can use Kinda-generated NIFs through `elixir_make`'s precompiled
  artifact flow.
  """

  @behaviour ElixirMake.Precompiler

  def current_target({:win32, _}) do
    # OTP reports the architecture as "win32" on all 64-bit Windows builds.
    # Zig-style triples are used for prebuilt asset naming.
    {:ok, "x86_64-windows-msvc"}
  end

  def current_target({:unix, _}) do
    # get current target triplet from `:erlang.system_info/1`
    system_architecture = to_string(:erlang.system_info(:system_architecture))

    case String.split(system_architecture, "-", trim: true) do
      [arch, _vendor, os, abi] ->
        {:ok, "#{arch}-#{os}-#{abi}"}

      [arch, vendor, os] ->
        normalized =
          if :os.type() == {:unix, :darwin} and String.starts_with?(os, "darwin"),
            do: "#{arch}-#{vendor}-darwin",
            else: system_architecture

        {:ok, normalized}

      _ ->
        {:error, "cannot decide current target"}
    end
  end

  @impl ElixirMake.Precompiler
  def current_target, do: current_target(:os.type())

  @impl ElixirMake.Precompiler
  def all_supported_targets(:fetch),
    do: ~w( aarch64-apple-darwin x86_64-apple-darwin x86_64-linux-gnu aarch64-linux-gnu x86_64-windows-msvc )

  def all_supported_targets(:compile) do
    {:ok, t} = current_target()
    [t]
  end

  @impl ElixirMake.Precompiler
  def build_native(args), do: ElixirMake.Compiler.compile(args)

  @impl ElixirMake.Precompiler
  def precompile(args, _target) do
    build_native(args)
    :ok
  end
end
