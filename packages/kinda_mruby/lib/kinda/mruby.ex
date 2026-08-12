defmodule Kinda.MRuby do
  @moduledoc "A lightweight embedded mruby 4 runtime."
  alias Kinda.MRuby.Native

  @spec version() :: String.t()
  def version, do: Native.version()

  @spec eval(iodata()) :: nil | boolean() | integer() | String.t()
  def eval(code), do: code |> IO.iodata_to_binary() |> Native.eval()
end
