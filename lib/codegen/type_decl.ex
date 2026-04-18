defmodule Kinda.CodeGen.TypeDecl do
  @moduledoc false

  alias Kinda.CodeGen.TypeSpecRef

  @type t() :: %__MODULE__{
          name: atom(),
          source_record_name: String.t() | nil,
          doc: String.t() | nil,
          typespec: TypeSpecRef.t()
        }

  defstruct name: nil, source_record_name: nil, doc: nil, typespec: nil
end
