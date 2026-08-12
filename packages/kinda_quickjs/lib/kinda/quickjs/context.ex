defmodule Kinda.QuickJS.Context do
  @moduledoc "A QuickJS realm owned by one runtime."
  alias Kinda.QuickJS.{Native, Value}
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec eval(t(), iodata(), keyword()) :: term()
  def eval(%__MODULE__{resource: context}, code, options \\ []) do
    budget = Keyword.get(options, :interrupt_budget, 0)
    Native.eval_context(context, IO.iodata_to_binary(code), budget)
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: context}), do: Native.close_context(context)

  @spec value(t(), iodata()) :: Value.t()
  def value(%__MODULE__{resource: context}, code) do
    %Value{resource: Native.create_value(context, IO.iodata_to_binary(code))}
  end
end
