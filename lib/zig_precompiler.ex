defmodule Kinda.Precompiler do
  @behaviour ElixirMake.Precompiler

  def current_target({:unix, _}) do
    # get current target triplet from `:erlang.system_info/1`
    system_architecture = to_string(:erlang.system_info(:system_architecture))
    current = String.split(system_architecture, "-", trim: true)

    case length(current) do
      4 ->
        {:ok, "#{Enum.at(current, 0)}-#{Enum.at(current, 2)}-#{Enum.at(current, 3)}"}

      3 ->
        case :os.type() do
          {:unix, :darwin} ->
            # could be something like aarch64-apple-darwin21.0.0
            # but we don't really need the last 21.0.0 part
            if String.match?(Enum.at(current, 2), ~r/^darwin.*/) do
              {:ok, "#{Enum.at(current, 0)}-#{Enum.at(current, 1)}-darwin"}
            else
              {:ok, system_architecture}
            end

          _ ->
            {:ok, system_architecture}
        end

      _ ->
        {:error, "cannot decide current target"}
    end
  end

  @impl ElixirMake.Precompiler
  def current_target do
    current_target(:os.type())
  end

  @impl ElixirMake.Precompiler
  def all_supported_targets(_operation) do
    ~w(
      aarch64-apple-darwin
      x86_64-unknown-linux-gnu
    )
  end

  @impl ElixirMake.Precompiler
  def build_native(args) do
    ElixirMake.Compiler.compile(args)
  end

  @impl ElixirMake.Precompiler
  def precompile(args, _target) do
    build_native(args)
    :ok
  end
end
