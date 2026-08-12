defmodule Kinda.QuickJS.Runtime do
  @moduledoc "An isolated QuickJS object heap serialized at the native boundary."
  alias Kinda.QuickJS.{Context, Native}
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec open(keyword()) :: t()
  def open(options \\ []) do
    memory_limit = Keyword.get(options, :memory_limit, 0)
    stack_limit = Keyword.get(options, :stack_limit, 0)
    %__MODULE__{resource: Native.create_runtime(memory_limit, stack_limit)}
  end

  @spec context(t()) :: Context.t()
  def context(%__MODULE__{resource: runtime}) do
    %Context{resource: Native.create_context(runtime)}
  end

  @spec stats(t()) :: %{
          allocations: non_neg_integer(),
          live_bytes: non_neg_integer(),
          limit: non_neg_integer()
        }
  def stats(%__MODULE__{resource: runtime}) do
    {allocations, live_bytes, limit} = Native.runtime_stats(runtime)
    %{allocations: allocations, live_bytes: live_bytes, limit: limit}
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: runtime}), do: Native.close_runtime(runtime)
end
