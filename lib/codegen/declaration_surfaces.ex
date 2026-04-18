defmodule Kinda.CodeGen.DeclarationSurfaces do
  @moduledoc false

  alias Kinda.CodeGen.{DeclarationManifest, NIFDecl, TypeDecl}

  @type source_declaration_manifest() :: DeclarationManifest.t() | nil

  @type t() :: %__MODULE__{
          source_declaration_manifest: source_declaration_manifest(),
          declaration_manifest: DeclarationManifest.t()
        }

  defstruct source_declaration_manifest: nil, declaration_manifest: nil

  @spec from_parts(source_declaration_manifest(), DeclarationManifest.t()) :: t()
  def from_parts(source_declaration_manifest, %DeclarationManifest{} = declaration_manifest) do
    %__MODULE__{
      source_declaration_manifest: source_declaration_manifest,
      declaration_manifest: declaration_manifest
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
    do: surfaces |> declaration_manifest() |> DeclarationManifest.signature_manifest()

  @spec nif_decls(t()) :: [NIFDecl.t()]
  def nif_decls(%__MODULE__{} = surfaces),
    do: surfaces |> declaration_manifest() |> DeclarationManifest.nif_decls()

  @spec type_decls(t()) :: [TypeDecl.t()]
  def type_decls(%__MODULE__{} = surfaces),
    do: surfaces |> declaration_manifest() |> DeclarationManifest.type_decls()
end
