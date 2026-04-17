defmodule Kinda.Wrapper.Manifest do
  @moduledoc """
  Framework-owned intermediate representation for wrapper extraction.
  """

  alias Kinda.Wrapper.Function

  defstruct functions: []

  @type t :: %__MODULE__{
          functions: [Function.t()]
        }
end
