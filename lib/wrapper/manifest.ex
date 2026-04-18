defmodule Kinda.Wrapper.Manifest do
  @moduledoc """
  Framework-owned intermediate representation for wrapper extraction.

  This is the first framework-level single source for extracted CAPI facts:
  function names, docs, parameter names, parameter C types, and return C types
  should all flow through this manifest before downstream policy projects them
  into public wrappers.
  """

  alias Kinda.Wrapper.Function

  defstruct functions: []

  @type t :: %__MODULE__{
          functions: [Function.t()]
        }
end
