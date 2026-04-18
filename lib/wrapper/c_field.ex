defmodule Kinda.Wrapper.CField do
  @moduledoc """
  Normalized C field fact extracted from a record declaration.
  """

  alias Kinda.Wrapper.CType

  @type t() :: %__MODULE__{
          name: String.t(),
          ctype: CType.t() | nil
        }

  defstruct name: nil, ctype: nil
end
