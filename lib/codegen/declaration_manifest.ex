defmodule Kinda.CodeGen.DeclarationManifest do
  @moduledoc false

  alias Kinda.CodeGen.NIFDecl
  alias Kinda.CodeGen.TypeDecl

  @type t() :: %__MODULE__{
          version: pos_integer(),
          signature_manifest_version: pos_integer() | nil,
          nif_decls: [NIFDecl.t()],
          type_decls: [TypeDecl.t()]
        }

  defstruct version: 1, signature_manifest_version: nil, nif_decls: [], type_decls: []

  @spec from_parts([NIFDecl.t()], [TypeDecl.t()], map() | nil) :: t()
  def from_parts(nif_decls, type_decls, signature_manifest \\ nil) do
    %__MODULE__{
      version: 1,
      signature_manifest_version:
        case signature_manifest do
          %{"version" => version} when is_integer(version) -> version
          _ -> nil
        end,
      nif_decls: nif_decls,
      type_decls: type_decls
    }
  end

  @spec from_manifest(map()) :: t()
  def from_manifest(%{} = manifest) do
    %__MODULE__{
      version: Map.get(manifest, "version", 1),
      signature_manifest_version: Map.get(manifest, "signature_manifest_version"),
      nif_decls: manifest |> Map.get("nif_decls", []) |> Enum.map(&NIFDecl.from_manifest/1),
      type_decls: manifest |> Map.get("type_decls", []) |> Enum.map(&TypeDecl.from_manifest/1)
    }
  end

  @spec to_manifest(t()) :: map()
  def to_manifest(%__MODULE__{} = declaration_manifest) do
    %{
      "version" => declaration_manifest.version,
      "signature_manifest_version" => declaration_manifest.signature_manifest_version,
      "nif_decls" => Enum.map(declaration_manifest.nif_decls, &NIFDecl.to_manifest/1),
      "type_decls" => Enum.map(declaration_manifest.type_decls, &TypeDecl.to_manifest/1)
    }
  end
end
