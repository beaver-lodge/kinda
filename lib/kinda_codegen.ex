defmodule Kinda.CodeGen do
  @moduledoc """
  Behavior and macros for declaration-driven NIF module generation.

  `use Kinda.CodeGen` requires a `codec:` module. Generated public wrappers
  call their concrete companion `Raw` function and pass only its return value
  to `codec.normalize/1`.
  """

  alias Kinda.Declaration

  alias Kinda.CodeGen.{
    DeclarationManifest,
    KindDecl,
    NIFDecl,
    TypeDecl,
    TypeSpecRef
  }

  @type declaration_surfaces :: Kinda.CodeGen.DeclarationSurfaces.t()

  defmacro __using__(opts) do
    quote do
      mod = Keyword.fetch!(unquote(opts), :with)
      root = Keyword.fetch!(unquote(opts), :root)
      codec = Keyword.fetch!(unquote(opts), :codec)
      Code.ensure_compiled!(mod)
      surfaces = Declaration.from_generator(mod, root)
      decls = Declaration.nif_decls(surfaces)
      type_decls = Declaration.type_decls(surfaces)

      {ast, mf} = Kinda.CodeGen.nif_ast_from_decls(decls, root, codec)

      (Kinda.CodeGen.type_decls_ast(type_decls) ++ ast)
      |> Code.eval_quoted([], __ENV__)

      Module.put_attribute(__MODULE__, :kinda_declaration_surfaces, surfaces)

      @doc false
      def __kinda_declaration_surfaces__, do: @kinda_declaration_surfaces

      mf
    end
  end

  @type nif_decl_input :: NIFDecl.t() | {atom(), integer()} | {atom(), [atom()]}
  @type signature_manifest :: map() | nil
  @type type_decl :: TypeDecl.t()
  @type declaration_manifest :: DeclarationManifest.t()
  @type declaration_manifest_source :: DeclarationManifest.source()

  @callback kinds() :: [KindDecl.t()]
  @callback declaration_manifest() :: declaration_manifest_source()
  @optional_callbacks kinds: 0
  def kinds(), do: []

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

  def nif_ast(kinds, nifs, root_module, codec) do
    kinds
    |> nif_decls(nifs, root_module)
    |> nif_ast_from_decls(root_module, codec)
  end

  def nif_ast_from_decls(decls, root_module, codec) do
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
            raw_args =
              Enum.map(args_ast, fn arg ->
                quote do
                  Kinda.unwrap_ref(unquote(arg))
                end
              end)

            raw_call = remote_call_ast(raw_module(root_module), wrapper_name, raw_args)

            quote do
              unquote(
                typespec_attribute_ast(wrapper_name, nif.param_typespecs, nif.return_typespec)
              )

              unquote(doc_attribute_ast(nif.doc))

              def unquote(wrapper_name)(unquote_splicing(args_ast)) do
                unquote(raw_call)
                |> unquote(codec).normalize()
              end
            end
          end

        raw_call = remote_call_ast(root_module, nif_name, args_ast)

        raw_entry_ast =
          quote do
            @doc false
            def unquote(wrapper_name)(unquote_splicing(args_ast)) do
              unquote(raw_call)
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

  def record_types_ast(signature_manifest),
    do: signature_manifest |> type_decls() |> type_decls_ast()

  def type_decls_ast(type_decls) when is_list(type_decls) do
    Enum.flat_map(type_decls, &type_decl_ast/1)
  end

  defp normalize_nif_decl(%NIFDecl{nif_name: nil, wrapper_name: wrapper_name} = nif, root_module)
       when not is_nil(wrapper_name) do
    %{nif | nif_name: Module.concat(root_module, wrapper_name)}
  end

  defp normalize_nif_decl(%NIFDecl{} = nif, _root_module), do: nif

  defp remote_call_ast(module, function, args) do
    {{:., [], [module, function]}, [], args}
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
