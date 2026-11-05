defmodule Kinda.CodeGen.DeclarationSurfaces do
  @moduledoc """
  The resolved declaration surfaces of a generator module.

  `from_generator/2` loads a generator module's declaration source (a module
  implementing `declaration_manifest/0` and optionally `kinds/0`) and resolves
  it into the source declaration manifest and the final declaration manifest,
  normalizing NIF declarations and merging the NIFs implied by resource kinds.
  """

  alias Kinda.CodeGen.{DeclarationManifest, NIFDecl, TypeDecl}

  @type source_declaration_manifest() :: DeclarationManifest.t() | nil

  @type t() :: %__MODULE__{
          source_declaration_manifest: source_declaration_manifest(),
          declaration_manifest: DeclarationManifest.t()
        }

  defstruct source_declaration_manifest: nil, declaration_manifest: nil

  @spec load_source(module()) :: source_declaration_manifest()
  def load_source(mod) when is_atom(mod) do
    Code.ensure_loaded!(mod)

    if function_exported?(mod, :declaration_manifest, 0) do
      mod.declaration_manifest() |> DeclarationManifest.load!()
    else
      raise Kinda.GenerationError,
        message: "generator module is missing its canonical declaration source",
        stage: :declaration_loading,
        reason: :missing_declaration_manifest,
        source: mod,
        expected: {:declaration_manifest, 0}
    end
  end

  @spec from_generator(module(), module()) :: t()
  def from_generator(mod, root_module) when is_atom(mod) and is_atom(root_module) do
    source = load_source(mod)
    from_parts(source, resolve_declaration_manifest(source, mod, root_module))
  end

  @spec from_parts(source_declaration_manifest(), DeclarationManifest.t()) :: t()
  def from_parts(source, %DeclarationManifest{} = manifest),
    do: %__MODULE__{source_declaration_manifest: source, declaration_manifest: manifest}

  @spec source_declaration_manifest(t()) :: source_declaration_manifest()
  def source_declaration_manifest(%__MODULE__{} = surfaces), do: surfaces.source_declaration_manifest

  @spec declaration_manifest(t()) :: DeclarationManifest.t()
  def declaration_manifest(%__MODULE__{} = surfaces), do: surfaces.declaration_manifest

  @spec signature_manifest(t()) :: map() | nil
  def signature_manifest(%__MODULE__{} = surfaces),
    do: surfaces |> declaration_manifest() |> DeclarationManifest.signature_manifest()

  @spec nif_decls(t()) :: [NIFDecl.t()]
  def nif_decls(%__MODULE__{} = surfaces), do: surfaces |> declaration_manifest() |> DeclarationManifest.nif_decls()

  @spec type_decls(t()) :: [TypeDecl.t()]
  def type_decls(%__MODULE__{} = surfaces), do: surfaces |> declaration_manifest() |> DeclarationManifest.type_decls()

  defp resolve_declaration_manifest(%DeclarationManifest{} = manifest, mod, root) do
    nifs = Kinda.CodeGen.nif_decls(kinds_for(mod), manifest.nif_decls, root)
    unique = Enum.uniq_by(nifs, &{&1.wrapper_name, &1.nif_name, &1.params})
    %{manifest | nif_decls: unique, type_decls: DeclarationManifest.type_decls(manifest)}
  end

  defp kinds_for(mod) do
    if function_exported?(mod, :kinds, 0), do: mod.kinds(), else: []
  end
end
