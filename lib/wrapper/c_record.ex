defmodule Kinda.Wrapper.CRecord do
  @moduledoc """
  Normalized C record declaration extracted from a wrapper surface.
  """

  alias Kinda.Wrapper.CField

  @type kind() :: :struct | :union | :record

  @type t() :: %__MODULE__{
          name: String.t(),
          kind: kind(),
          fields: [CField.t()]
        }

  defstruct name: nil, kind: :record, fields: []
end
