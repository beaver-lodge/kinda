defmodule Kinda.QuickJS do
  @moduledoc "A lightweight embedded QuickJS runtime."
  alias Kinda.QuickJS.{Context, Native, Runtime}

  @spec open(keyword()) :: Runtime.t()
  def open(options \\ []), do: Runtime.open(options)

  @spec context(Runtime.t()) :: Context.t()
  def context(runtime), do: Runtime.context(runtime)

  @spec eval(Context.t(), iodata(), keyword()) :: term()
  def eval(context, code, options \\ []), do: Context.eval(context, code, options)

  @spec version() :: String.t()
  def version, do: Native.version()

  @spec eval(iodata()) :: :undefined | nil | boolean() | integer() | float() | String.t()
  def eval(code), do: code |> IO.iodata_to_binary() |> Native.eval()
end
