defmodule Kinda.Wrapper.Manifest do
  @moduledoc """
  Framework-owned intermediate representation for wrapper extraction.

  This is the first framework-level single source for extracted CAPI facts:
  function names, docs, parameter names, parameter C types, return C types,
  and named record declarations should all flow through this manifest before
  downstream policy projects them into public wrappers.
  """

  alias Kinda.Wrapper.CRecord
  alias Kinda.Wrapper.Function

  defstruct functions: [], records: []

  @type t :: %__MODULE__{
          functions: [Function.t()],
          records: [CRecord.t()]
        }
end
