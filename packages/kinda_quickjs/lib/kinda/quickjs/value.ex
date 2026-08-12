defmodule Kinda.QuickJS.Value do
  @moduledoc "A persistent QuickJS value owned by its originating context."
  alias Kinda.QuickJS.Native
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec to_term(t()) :: term()
  def to_term(%__MODULE__{resource: value}), do: Native.export_value(value)

  @spec promise_state(t()) :: :pending | :fulfilled | :rejected | :not_promise
  def promise_state(%__MODULE__{resource: value}), do: Native.promise_state(value)

  @spec promise_result(t()) :: term()
  def promise_result(%__MODULE__{resource: value}), do: Native.promise_result(value)

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: value}), do: Native.close_value(value)
end
