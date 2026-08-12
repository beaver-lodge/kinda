defmodule Kinda.MRuby.VM do
  @moduledoc "An isolated mruby state serialized across calls from the BEAM."
  alias Kinda.MRuby.{Bytecode, Native, Value}
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec open(keyword()) :: t()
  def open(options \\ []) do
    resource =
      case Keyword.fetch(options, :allocation_budget) do
        {:ok, budget} when is_integer(budget) and budget >= 0 -> Native.create_limited_vm(budget)
        :error -> Native.create_vm()
      end

    %__MODULE__{resource: resource}
  end

  @spec allocator_stats(t()) :: %{
          allocations: non_neg_integer(),
          live_bytes: non_neg_integer(),
          peak_bytes: non_neg_integer()
        }
  def allocator_stats(%__MODULE__{resource: resource}) do
    {allocations, live_bytes, peak_bytes} = Native.allocator_stats(resource)
    %{allocations: allocations, live_bytes: live_bytes, peak_bytes: peak_bytes}
  end

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
