defmodule Kinda.Python.Interpreter do
  @moduledoc "An isolated CPython interpreter with its own GIL and module state."
  alias Kinda.Python.{Native, Value}
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}
  @spec open() :: t()
  def open, do: %__MODULE__{resource: Native.create_interpreter()}
  @spec eval(t(), iodata()) :: Value.t()
  def eval(%__MODULE__{resource: resource}, code),
    do: %Value{resource: Native.eval(resource, IO.iodata_to_binary(code))}

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.close_interpreter(resource)
end
