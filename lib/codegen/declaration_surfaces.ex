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
      raise ArgumentError,
            "#{inspect(mod)} must implement declaration_manifest/0 as the canonical source contract"
    end
  end

  @spec from_generator(module(), module()) :: t()
  def from_generator(mod, root_module) when is_atom(mod) and is_atom(root_module) do
    source_declaration_manifest = load_source(mod)

    declaration_manifest =
      resolve_declaration_manifest(
        source_declaration_manifest,
        mod,
        root_module
      )

    from_parts(source_declaration_manifest, declaration_manifest)
  end

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

  defp resolve_declaration_manifest(
         %DeclarationManifest{} = declaration_manifest,
         mod,
         root_module
       ) do
    declaration_manifest
    |> DeclarationManifest.put_nif_decls(
      declaration_manifest
      |> DeclarationManifest.nif_decls()
      |> Enum.map(&normalize_nif_decl(&1, root_module))
    )
    |> DeclarationManifest.merge_nif_decls(nif_decls(kinds_for(mod), [], root_module))
    |> then(&DeclarationManifest.put_type_decls(&1, DeclarationManifest.type_decls(&1)))
  end

  defp nif_decls(kinds, nifs, root_module) do
    extra_kind_nifs =
      kinds
      |> Enum.map(&NIFDecl.from_resource_kind/1)
      |> List.flatten()

    for nif <- nifs ++ extra_kind_nifs do
      case nif do
        {wrapper_name, arity} when is_atom(wrapper_name) and is_integer(arity) ->
          %NIFDecl{
            wrapper_name: wrapper_name,
            nif_name: Module.concat(root_module, wrapper_name),
            params: arity
          }

        {wrapper_name, params} when is_atom(wrapper_name) and is_list(params) ->
          %NIFDecl{
            wrapper_name: wrapper_name,
            nif_name: Module.concat(root_module, wrapper_name),
            params: params
          }

        %NIFDecl{} ->
          normalize_nif_decl(nif, root_module)
      end
    end
  end

  defp normalize_nif_decl(%NIFDecl{nif_name: nil, wrapper_name: wrapper_name} = nif, root_module)
       when not is_nil(wrapper_name) do
    %{nif | nif_name: Module.concat(root_module, wrapper_name)}
  end

  defp normalize_nif_decl(%NIFDecl{} = nif, _root_module), do: nif

  defp kinds_for(mod) do
    if function_exported?(mod, :kinds, 0), do: mod.kinds(), else: []
  end
end
