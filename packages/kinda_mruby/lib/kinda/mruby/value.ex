defmodule Kinda.MRuby.Value do
  @moduledoc "An opaque mruby value rooted in, and owned by, one VM."
  alias Kinda.MRuby.Native
  @enforce_keys [:resource]
  defstruct [:resource]
  @opaque t :: %__MODULE__{resource: reference()}

  @spec to_term(t()) :: nil | boolean() | integer() | String.t()
  def to_term(%__MODULE__{resource: resource}), do: Native.value_to_term(resource)

  @spec close(t()) :: :ok
  def close(%__MODULE__{resource: resource}), do: Native.close_value(resource)
end
