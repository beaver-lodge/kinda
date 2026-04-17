defmodule Kinda.Wrapper.Function do
  @moduledoc """
  Normalized function declaration extracted from a wrapper surface.
  """

  @enforce_keys [:name, :params, :arity]
  defstruct [:name, :params, :arity]

  @type t :: %__MODULE__{
          name: String.t(),
          params: [String.t()],
          arity: non_neg_integer()
        }
end
