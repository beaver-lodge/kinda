defmodule Kinda.CodeGen do
  @moduledoc """
  Behavior for customizing your source code generation.
  """

  alias Kinda.CodeGen.{
    DeclarationManifest,
    DeclarationSurfaces,
    KindDecl,
    NIFDecl,
    TypeDecl,
    TypeSpecRef
  }

  @type declaration_surfaces :: DeclarationSurfaces.t()

  defmacro __using__(opts) do
    quote do
      mod = Keyword.fetch!(unquote(opts), :with)
      root = Keyword.fetch!(unquote(opts), :root)
      forward = Keyword.fetch!(unquote(opts), :forward)
      Code.ensure_compiled!(mod)
      surfaces = Kinda.CodeGen.declaration_surfaces(mod, root)
      decls = Kinda.CodeGen.DeclarationSurfaces.nif_decls(surfaces)
      type_decls = Kinda.CodeGen.DeclarationSurfaces.type_decls(surfaces)
      declaration_manifest = Kinda.CodeGen.DeclarationSurfaces.declaration_manifest(surfaces)
      signature_manifest = Kinda.CodeGen.DeclarationSurfaces.signature_manifest(surfaces)

      {ast, mf} = Kinda.CodeGen.nif_ast_from_decls(decls, root, forward)

      (Kinda.CodeGen.type_decls_ast(type_decls) ++ ast)
      |> Code.eval_quoted([], __ENV__)

      Module.put_attribute(__MODULE__, :kinda_declaration_surfaces, surfaces)

      @doc false
      def __kinda_declaration_surfaces__, do: @kinda_declaration_surfaces

      @doc false
      def __kinda_source_declaration_manifest__ do
        @kinda_declaration_surfaces
        |> Kinda.CodeGen.DeclarationSurfaces.source_declaration_manifest()
      end

      @doc false
      def __kinda_nif_decls__ do
        @kinda_declaration_surfaces
        |> Kinda.CodeGen.DeclarationSurfaces.nif_decls()
      end

      @doc false
      def __kinda_signature_manifest__ do
        @kinda_declaration_surfaces
        |> Kinda.CodeGen.DeclarationSurfaces.signature_manifest()
      end

      @doc false
      def __kinda_type_decls__ do
        @kinda_declaration_surfaces
        |> Kinda.CodeGen.DeclarationSurfaces.type_decls()
      end

      @doc false
      def __kinda_declaration_manifest__ do
        @kinda_declaration_surfaces
        |> Kinda.CodeGen.DeclarationSurfaces.declaration_manifest()
      end

      mf
    end
  end

  @type nif_decl_input :: NIFDecl.t() | {atom(), integer()} | {atom(), [atom()]}
  @type signature_manifest :: map() | nil
  @type type_decl :: TypeDecl.t()
  @type declaration_manifest :: DeclarationManifest.t()
  @type declaration_manifest_source :: DeclarationManifest.source()

  @callback kinds() :: [KindDecl.t()]
  @callback nifs() :: [nif_decl_input()]
  @callback signature_manifest() :: signature_manifest()
  @callback declaration_manifest() :: declaration_manifest_source()
  @optional_callbacks kinds: 0, nifs: 0, signature_manifest: 0, declaration_manifest: 0
  def kinds(), do: []
  def nifs(), do: []

  @spec source_declaration_manifest(module()) :: declaration_manifest() | nil
  def source_declaration_manifest(mod) when is_atom(mod) do
    if function_exported?(mod, :declaration_manifest, 0),
      do: load_declaration_manifest(mod.declaration_manifest()),
      else: nil
  end

  @spec source_signature_manifest(module(), declaration_manifest() | nil) :: signature_manifest()
  def source_signature_manifest(mod, source_declaration_manifest \\ nil)

  def source_signature_manifest(mod, nil) when is_atom(mod) do
    cond do
      function_exported?(mod, :signature_manifest, 0) -> mod.signature_manifest()
      true -> nil
    end
  end

  def source_signature_manifest(mod, %DeclarationManifest{} = source_declaration_manifest)
      when is_atom(mod) do
    DeclarationManifest.signature_manifest(source_declaration_manifest) ||
      source_signature_manifest(mod, nil)
  end

  @spec declaration_surfaces(module(), module()) :: declaration_surfaces()
  def declaration_surfaces(mod, root_module) when is_atom(mod) and is_atom(root_module) do
    source_declaration_manifest = source_declaration_manifest(mod)
    signature_manifest = source_signature_manifest(mod, source_declaration_manifest)

    {decls, type_decls, declaration_manifest} =
      resolve_declaration_surfaces(
        source_declaration_manifest,
        mod,
        root_module,
        signature_manifest
      )

    DeclarationSurfaces.from_parts(
      source_declaration_manifest,
      declaration_manifest,
      decls,
      type_decls,
      signature_manifest
    )
  end

  def raw_module(root_module) when is_atom(root_module) do
    Module.concat(root_module, Raw)
  end

  def nif_decls(kinds, nifs, root_module) do
    # generate stubs for generated NIFs
    extra_kind_nifs =
      kinds
      |> Enum.map(&NIFDecl.from_resource_kind/1)
      |> List.flatten()

    nifs = nifs ++ extra_kind_nifs

    for nif <- nifs do
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

  def nif_ast(kinds, nifs, root_module, forward_module) do
    kinds
    |> nif_decls(nifs, root_module)
    |> nif_ast_from_decls(root_module, forward_module)
  end

  def nif_ast_from_decls(decls, root_module, forward_module) do
    {entries, raw_entries} =
      for nif <- decls do
        {args_ast, arity} =
          if is_list(nif.params) do
            {Enum.map(nif.params, &Macro.var(&1, __MODULE__)), length(nif.params)}
          else
            {Macro.generate_unique_arguments(nif.params, __MODULE__), nif.params}
          end

        %NIFDecl{wrapper_name: wrapper_name, nif_name: nif_name} = nif

        wrapper_name =
          if is_bitstring(wrapper_name) do
            String.to_atom(wrapper_name)
          else
            wrapper_name
          end

        wrapper_ast =
          if nif_name != wrapper_name do
            quote do
              unquote(
                typespec_attribute_ast(wrapper_name, nif.param_typespecs, nif.return_typespec)
              )

              unquote(doc_attribute_ast(nif.doc))

              def unquote(wrapper_name)(unquote_splicing(args_ast)) do
                Kinda.Forwarder.invoke_public_nif(
                  unquote(forward_module),
                  unquote(raw_module(root_module)),
                  unquote(wrapper_name),
                  [unquote_splicing(args_ast)]
                )
              end
            end
          end

        raw_entry_ast =
          quote do
            @doc false
            def unquote(wrapper_name)(unquote_splicing(args_ast)) do
              apply(unquote(root_module), unquote(nif_name), [unquote_splicing(args_ast)])
            end
          end

        ast =
          quote do
            unquote(
              if(nif_name == wrapper_name,
                do:
                  typespec_attribute_ast(wrapper_name, nif.param_typespecs, nif.return_typespec),
                else: nil
              )
            )

            unquote(doc_attribute_ast(if(nif_name == wrapper_name, do: nif.doc, else: false)))

            def unquote(nif_name)(unquote_splicing(args_ast)),
              do: :erlang.nif_error(:not_loaded)

            unquote(wrapper_ast)
          end

        {{ast, {nif_name, arity}}, raw_entry_ast}
      end
      |> Enum.unzip()

    {asts, exports} = Enum.unzip(entries)

    raw_module_ast =
      case Enum.reject(raw_entries, &is_nil/1) do
        [] ->
          nil

        raw_entries ->
          quote do
            defmodule Raw do
              (unquote_splicing(raw_entries))
            end
          end
      end

    {asts ++ List.wrap(raw_module_ast), exports}
  end

  def type_decls(%DeclarationManifest{} = declaration_manifest),
    do: DeclarationManifest.type_decls(declaration_manifest)

  def type_decls(nil), do: []

  def type_decls(signature_manifest), do: TypeDecl.from_signature_manifest(signature_manifest)

  def declaration_manifest(nif_decls, type_decls, signature_manifest \\ nil) do
    DeclarationManifest.from_parts(nif_decls, type_decls, signature_manifest)
  end

  def load_declaration_manifest(declaration_manifest), do: DeclarationManifest.load!(declaration_manifest)

  def resolve_declaration_surfaces(nil, mod, root_module, signature_manifest) do
    decls = nif_decls(kinds_for(mod), nifs_for(mod), root_module)
    declaration_manifest = DeclarationManifest.build(decls, signature_manifest)
    type_decls = type_decls(declaration_manifest)
    {decls, type_decls, declaration_manifest}
  end

  def resolve_declaration_surfaces(
        %DeclarationManifest{} = declaration_manifest,
        mod,
        root_module,
        signature_manifest
      ) do
    declaration_manifest =
      declaration_manifest
      |> DeclarationManifest.put_nif_decls(
        declaration_manifest
        |> DeclarationManifest.nif_decls()
        |> Enum.map(&normalize_nif_decl(&1, root_module))
      )
      |> DeclarationManifest.merge_nif_decls(nif_decls(kinds_for(mod), [], root_module))
      |> DeclarationManifest.put_signature_manifest(signature_manifest)
      |> then(&DeclarationManifest.put_type_decls(&1, DeclarationManifest.type_decls(&1)))

    decls = DeclarationManifest.nif_decls(declaration_manifest)
    type_decls = DeclarationManifest.type_decls(declaration_manifest)

    {decls, type_decls, declaration_manifest}
  end

  def record_types_ast(signature_manifest), do: signature_manifest |> type_decls() |> type_decls_ast()

  def type_decls_ast(type_decls) when is_list(type_decls) do
    Enum.flat_map(type_decls, &type_decl_ast/1)
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

  defp doc_attribute_ast(nil), do: nil

  defp doc_attribute_ast(false) do
    quote do
      @doc false
    end
  end

  defp doc_attribute_ast(doc) do
    quote do
      @doc unquote(doc)
    end
  end

  defp typespec_attribute_ast(_name, nil, _return_type), do: nil
  defp typespec_attribute_ast(_name, _params, nil), do: nil

  defp typespec_attribute_ast(name, params, return_type) do
    quote do
      @spec unquote(name)(unquote_splicing(Enum.map(params, &TypeSpecRef.to_quoted/1))) ::
              unquote(TypeSpecRef.to_quoted(return_type))
    end
  end

  defp type_decl_ast(%TypeDecl{name: name, doc: doc, typespec: typespec}) do
    [
      quote do
        @typedoc unquote(doc)
      end,
      quote do
        @type unquote(name)() :: unquote(TypeSpecRef.to_quoted(typespec))
      end
    ]
  end
end
