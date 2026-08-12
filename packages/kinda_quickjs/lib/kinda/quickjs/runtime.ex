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

  @spec run_jobs(t(), non_neg_integer()) :: non_neg_integer()
  def run_jobs(%__MODULE__{resource: runtime}, limit \\ 0), do: Native.run_jobs(runtime, limit)

  @spec register_module(t(), iodata(), iodata()) :: :ok
  def register_module(%__MODULE__{resource: runtime}, name, source) do
    Native.register_module(runtime, IO.iodata_to_binary(name), IO.iodata_to_binary(source))
  end
end
