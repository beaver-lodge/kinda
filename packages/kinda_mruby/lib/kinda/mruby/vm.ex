defmodule Kinda.MRuby.VM do
  @moduledoc "An isolated mruby state serialized across calls from the BEAM."
  alias Kinda.MRuby.{Bytecode, Native, Value}
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec open() :: t()
  def open, do: %__MODULE__{resource: Native.create_vm()}

  @spec eval(t(), iodata()) :: Value.t()
  def eval(%__MODULE__{resource: resource}, code) do
    %Value{resource: Native.eval_value(resource, IO.iodata_to_binary(code))}
  end

  @spec run(t(), Bytecode.t()) :: Value.t()
  def run(%__MODULE__{resource: vm}, %Bytecode{resource: bytecode}) do
    %Value{resource: Native.run_bytecode(vm, bytecode)}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.close_vm(resource)
end
