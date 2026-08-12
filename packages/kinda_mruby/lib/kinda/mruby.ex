defmodule Kinda.MRuby do
  @moduledoc "A lightweight embedded mruby 4 runtime."
  alias Kinda.MRuby.Native

  @spec open() :: Kinda.MRuby.VM.t()
  defdelegate open(), to: Kinda.MRuby.VM

  @spec eval(Kinda.MRuby.VM.t(), iodata()) :: Kinda.MRuby.Value.t()
  defdelegate eval(vm, code), to: Kinda.MRuby.VM

  @spec compile(iodata()) :: Kinda.MRuby.Bytecode.t()
  defdelegate compile(code), to: Kinda.MRuby.Bytecode

  @spec run(Kinda.MRuby.VM.t(), Kinda.MRuby.Bytecode.t()) :: Kinda.MRuby.Value.t()
  defdelegate run(vm, bytecode), to: Kinda.MRuby.VM

  @spec version() :: String.t()
  def version, do: Native.version()

  @spec eval(iodata()) :: nil | boolean() | integer() | String.t()
  def eval(code), do: code |> IO.iodata_to_binary() |> Native.eval()
end
