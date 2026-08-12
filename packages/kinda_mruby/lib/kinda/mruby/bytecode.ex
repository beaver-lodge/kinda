defmodule Kinda.MRuby.Bytecode do
  @moduledoc "Version-bound mruby bytecode that can execute in multiple VMs."
  alias Kinda.MRuby.Native
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec compile(iodata()) :: t()
  def compile(code) do
    %__MODULE__{resource: Native.compile_bytecode(IO.iodata_to_binary(code))}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.close_bytecode(resource)
end
