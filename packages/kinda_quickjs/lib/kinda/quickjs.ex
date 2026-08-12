defmodule Kinda.QuickJS do
  @moduledoc "A lightweight embedded QuickJS runtime."
  alias Kinda.QuickJS.Native

  @spec version() :: String.t()
  def version, do: Native.version()

  @spec eval(iodata()) :: :undefined | nil | boolean() | integer() | float() | String.t()
  def eval(code), do: code |> IO.iodata_to_binary() |> Native.eval()
end
