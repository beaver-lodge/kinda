defmodule Kinda.CodeGen.DeclarationSurfaces do
  @moduledoc false

  alias Kinda.CodeGen.{DeclarationManifest, NIFDecl, TypeDecl}

  @type source_declaration_manifest() :: DeclarationManifest.t() | nil

  @type t() :: %__MODULE__{
          source_declaration_manifest: source_declaration_manifest(),
          declaration_manifest: DeclarationManifest.t()
        }

  defstruct source_declaration_manifest: nil, declaration_manifest: nil

  @spec load_source(module()) :: source_declaration_manifest()
  def load_source(mod) when is_atom(mod) do
    if function_exported?(mod, :declaration_manifest, 0),
      do: mod.declaration_manifest() |> DeclarationManifest.load!(),
      else: nil
  end

  @spec source_signature(module(), source_declaration_manifest()) :: map() | nil
  def source_signature(mod, source_declaration_manifest \\ nil)

  def source_signature(mod, nil) when is_atom(mod) do
    if function_exported?(mod, :signature_manifest, 0), do: mod.signature_manifest(), else: nil
  end

  def source_signature(mod, %DeclarationManifest{} = source_declaration_manifest) when is_atom(mod) do
    DeclarationManifest.signature_manifest(source_declaration_manifest) ||
      source_signature(mod, nil)
  end

  @spec from_generator(module(), module()) :: t()
  def from_generator(mod, root_module) when is_atom(mod) and is_atom(root_module) do
    source_declaration_manifest = load_source(mod)
    signature_manifest = source_signature(mod, source_declaration_manifest)

    declaration_manifest =
      resolve_declaration_manifest(
        source_declaration_manifest,
        mod,
        root_module,
        signature_manifest
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

  defp resolve_declaration_manifest(nil, mod, root_module, signature_manifest) do
    decls = nif_decls(kinds_for(mod), nifs_for(mod), root_module)
    DeclarationManifest.build(decls, signature_manifest)
  end

  defp resolve_declaration_manifest(
         %DeclarationManifest{} = declaration_manifest,
         mod,
         root_module,
         signature_manifest
       ) do
    declaration_manifest
    |> DeclarationManifest.put_nif_decls(
      declaration_manifest
      |> DeclarationManifest.nif_decls()
      |> Enum.map(&normalize_nif_decl(&1, root_module))
    )
    |> DeclarationManifest.merge_nif_decls(nif_decls(kinds_for(mod), [], root_module))
    |> DeclarationManifest.put_signature_manifest(signature_manifest)
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

  defp nifs_for(mod) do
    if function_exported?(mod, :nifs, 0), do: mod.nifs(), else: []
  end
end
