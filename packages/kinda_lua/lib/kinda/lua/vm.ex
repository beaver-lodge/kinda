defmodule Kinda.Lua.VM do
  @moduledoc "An isolated, serialized Lua state."
  alias Kinda.Lua.Native
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec open(keyword()) :: t()
  def open(options \\ []) do
    budget = Keyword.get(options, :memory_limit, 0)
    %__MODULE__{resource: Native.create_vm(budget)}
  end

  @spec eval(t(), iodata()) :: term()
  def eval(%__MODULE__{resource: resource}, code) do
    case Native.eval_vm(resource, IO.iodata_to_binary(code)) do
      [value] -> value
      values -> values
    end
  end

  @spec allocator_stats(t()) :: %{
          calls: non_neg_integer(),
          live_bytes: non_neg_integer(),
          peak_bytes: non_neg_integer()
        }
  def allocator_stats(%__MODULE__{resource: resource}) do
    {calls, live_bytes, peak_bytes} = Native.allocator_stats(resource)
    %{calls: calls, live_bytes: live_bytes, peak_bytes: peak_bytes}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.close_vm(resource)
end
