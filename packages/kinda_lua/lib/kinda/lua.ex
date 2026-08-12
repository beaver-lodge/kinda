defmodule Kinda.Lua do
  @moduledoc "A lightweight embedded Lua 5.4 runtime."
  alias Kinda.Lua.{Native, VM}

  @spec open(keyword()) :: VM.t()
  def open(options \\ []), do: VM.open(options)

  @spec eval(VM.t(), iodata()) :: term()
  def eval(vm, code), do: VM.eval(vm, code)

  @spec version() :: String.t()
  def version, do: Native.version()

  @spec eval(iodata()) :: nil | boolean() | integer() | float() | String.t()
  def eval(code), do: code |> IO.iodata_to_binary() |> Native.eval()
end
