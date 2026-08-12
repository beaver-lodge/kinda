defmodule Kinda.Lua.Bytecode do
  @moduledoc "Lua 5.4.8-bound bytecode that can execute in multiple VMs."
  alias Kinda.Lua.Native
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec compile(iodata()) :: t()
  def compile(code), do: %__MODULE__{resource: Native.compile_bytecode(IO.iodata_to_binary(code))}

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.close_bytecode(resource)
end
