defmodule Kinda.CodeGen.DeclarationSurfaces do
  @moduledoc false

  alias Kinda.CodeGen.{DeclarationManifest, NIFDecl, TypeDecl}

  @type source_declaration_manifest() :: DeclarationManifest.t() | nil

  @type t() :: %__MODULE__{
          source_declaration_manifest: source_declaration_manifest(),
          declaration_manifest: DeclarationManifest.t(),
          signature_manifest: map() | nil,
          nif_decls: [NIFDecl.t()],
          type_decls: [TypeDecl.t()]
        }

  defstruct source_declaration_manifest: nil,
            declaration_manifest: nil,
            signature_manifest: nil,
            nif_decls: [],
            type_decls: []

  @spec from_parts(
          source_declaration_manifest(),
          DeclarationManifest.t(),
          [NIFDecl.t()],
          [TypeDecl.t()],
          map() | nil
        ) :: t()
  def from_parts(
        source_declaration_manifest,
        %DeclarationManifest{} = declaration_manifest,
        nif_decls,
        type_decls,
        signature_manifest
      ) do
    %__MODULE__{
      source_declaration_manifest: source_declaration_manifest,
      declaration_manifest: declaration_manifest,
      signature_manifest: signature_manifest,
      nif_decls: nif_decls,
      type_decls: type_decls
    }
  end

  @spec source_declaration_manifest(t()) :: source_declaration_manifest()
  def source_declaration_manifest(%__MODULE__{} = surfaces),
    do: surfaces.source_declaration_manifest

  @spec declaration_manifest(t()) :: DeclarationManifest.t()
  def declaration_manifest(%__MODULE__{} = surfaces),
    do: surfaces.declaration_manifest

  @spec signature_manifest(t()) :: map() | nil
  def signature_manifest(%__MODULE__{} = surfaces),
    do: surfaces.signature_manifest

  @spec nif_decls(t()) :: [NIFDecl.t()]
  def nif_decls(%__MODULE__{} = surfaces),
    do: surfaces.nif_decls

  @spec type_decls(t()) :: [TypeDecl.t()]
  def type_decls(%__MODULE__{} = surfaces),
    do: surfaces.type_decls
end
