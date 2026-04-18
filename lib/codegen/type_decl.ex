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

  @spec from_signature_manifest(map() | nil) :: [t()]
  def from_signature_manifest(nil), do: []

  def from_signature_manifest(%{"records" => records}) when is_list(records) do
    Enum.flat_map(records, &from_record_manifest/1)
  end

  def from_signature_manifest(_manifest), do: []

  @spec to_manifest(t()) :: map()
  def to_manifest(%__MODULE__{} = type_decl) do
    %{
      "name" => Atom.to_string(type_decl.name),
      "source_record_name" => type_decl.source_record_name,
      "doc" => type_decl.doc,
      "typespec" => TypeSpecRef.to_manifest(type_decl.typespec)
    }
  end

  @spec from_record_manifest(map()) :: [t()]
  def from_record_manifest(%{"name" => name, "public_typespec" => public_typespec})
      when is_binary(name) and is_map(public_typespec) do
    [
      %__MODULE__{
        name: record_type_name(name),
        source_record_name: name,
        doc: "Typed projection for extracted C record #{name}.",
        typespec: TypeSpecRef.from_manifest(public_typespec)
      }
    ]
  end

  def from_record_manifest(_record), do: []

  defp record_type_name(record_name) do
    record_name
    |> Macro.underscore()
    |> Kernel.<>("_record")
    |> String.to_atom()
  end
end
