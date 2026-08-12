defmodule Kinda.Lua do
  @moduledoc "A lightweight embedded Lua 5.4 runtime."
  alias Kinda.Lua.{Bytecode, Coroutine, Native, Userdata, VM}

  @spec open(keyword()) :: VM.t()
  def open(options \\ []), do: VM.open(options)

  @spec eval(VM.t(), iodata()) :: term()
  def eval(vm, code), do: VM.eval(vm, code)

  @spec coroutine(VM.t(), iodata()) :: Coroutine.t()
  def coroutine(vm, code), do: Coroutine.new(vm, code)

  @spec compile(iodata()) :: Bytecode.t()
  def compile(code), do: Bytecode.compile(code)

  @spec run(VM.t(), Bytecode.t()) :: term()
  def run(vm, bytecode), do: VM.run(vm, bytecode)

  @spec userdata(VM.t(), integer()) :: Userdata.t()
  def userdata(vm, value), do: Userdata.new(vm, value)

  @spec version() :: String.t()
  def version, do: Native.version()

  @spec eval(iodata()) :: nil | boolean() | integer() | float() | String.t()
  def eval(code), do: code |> IO.iodata_to_binary() |> Native.eval()
end
