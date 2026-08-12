defmodule Kinda.Python do
  @moduledoc """
  Embedded CPython 3.14 runtime information.

  The runtime is initialized once per BEAM process and intentionally remains
  alive until the operating system tears down the process. Interpreter
  resources are introduced in the next package layer.
  """

  alias Kinda.Python.{Execution, Native}

  @spec open() :: Kinda.Python.Interpreter.t()
  defdelegate open(), to: Kinda.Python.Interpreter

  @spec eval(Kinda.Python.Interpreter.t(), iodata()) :: Kinda.Python.Value.t()
  defdelegate eval(interpreter, code), to: Kinda.Python.Interpreter

  @spec eval_async(iodata()) :: Execution.t()
  def eval_async(code), do: Execution.start(code)

  @spec version() :: String.t()
  def version, do: Native.version()

  @spec initialized?() :: boolean()
  def initialized?, do: Native.initialized?()

  @spec free_threaded_build?() :: boolean()
  def free_threaded_build?, do: Native.free_threaded_build?()
end
