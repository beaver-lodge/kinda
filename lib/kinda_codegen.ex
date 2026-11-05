defmodule Kinda.CodeGen do
  @moduledoc """
  Behavior and macros for declaration-driven NIF module generation.

  `use Kinda.CodeGen` requires a `codec:` module. Generated public wrappers
  call their concrete raw NIF function and pass only its return value to
  `codec.normalize/1`.

  The default `:combined` surface keeps public wrappers, native stubs, and a
  raw proxy module together. Large bindings can compile the `:public` and
  `:raw` surfaces in separate modules to remove the proxy layer and let the
  compiler process both surfaces independently.
  """

  alias Kinda.Declaration

  alias Kinda.CodeGen.{DeclarationManifest, KindDecl, NIFDecl, TypeDecl, TypeSpecRef}

  @type declaration_surfaces :: Kinda.CodeGen.DeclarationSurfaces.t()

  defmacro __using__(opts), do: quote(do: Kinda.CodeGen.define(unquote(opts), __ENV__))

  @doc false
  def define(opts, env) do
    mod = Keyword.fetch!(opts, :with)
    root = Keyword.fetch!(opts, :root)
    codec = Keyword.fetch!(opts, :codec)
    Code.ensure_compiled!(mod)
    surfaces = Declaration.from_generator(mod, root)
    decls = Declaration.nif_decls(surfaces)
    surface = Keyword.get(opts, :surface, :combined)

    {ast, exports} =
      case surface do
        :combined ->
          nif_ast_from_decls(decls, root, codec)

        :public ->
          public_nif_ast_from_decls(decls, Keyword.fetch!(opts, :raw_module), codec)

        :raw ->
          raw_nif_ast_from_decls(decls)

        other ->
          raise Kinda.GenerationError,
            message: "unsupported code generation surface",
            stage: :module_generation,
            reason: :invalid_surface,
            expected: [:combined, :public, :raw],
            actual: other
      end

    metadata =
      if surface == :raw do
        []
      else
        [
          quote do
            @doc false
            def __kinda_declaration_surfaces__, do: Kinda.Declaration.from_generator(unquote(mod), unquote(root))
          end
          | type_decls_ast(Declaration.type_decls(surfaces))
        ]
      end

    Code.eval_quoted(metadata ++ ast, [], env)
    exports
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

  def raw_module(root_module) when is_atom(root_module), do: Module.concat(root_module, Raw)

  def nif_decls(kinds, nifs, root_module) do
    for nif <- nifs ++ Enum.flat_map(kinds, &NIFDecl.from_resource_kind/1) do
      case nif do
        {name, params} when is_atom(name) and (is_integer(params) or is_list(params)) ->
          %NIFDecl{wrapper_name: name, nif_name: Module.concat(root_module, name), params: params}

        %NIFDecl{} ->
          normalize_nif_decl(nif, root_module)
      end
    end
  end

  def nif_ast_from_decls(decls, root_module, codec) do
    {entries, proxies} =
      Enum.map(decls, fn nif ->
        {args, arity} = arguments_for(nif)
        name = normalize_function_name(nif.wrapper_name)
        public? = nif.nif_name != name

        wrapper =
          if public?, do: wrapper_ast(nif, name, args, arity, raw_module(root_module), codec)

        raw_call = remote_call_ast(root_module, nif.nif_name, args)

        proxy =
          quote do
            @doc false
            def unquote(name)(unquote_splicing(args)), do: unquote(raw_call)
          end

        ast =
          quote do
            unquote(if not public?, do: typespec_attribute_ast(name, nif.param_typespecs, nif.return_typespec))

            unquote(doc_attribute_ast(if public?, do: false, else: nif.doc))
            def unquote(nif.nif_name)(unquote_splicing(args)), do: :erlang.nif_error(:not_loaded)
            unquote(wrapper)
          end

        {{ast, {nif.nif_name, arity}}, proxy}
      end)
      |> Enum.unzip()

    {asts, exports} = Enum.unzip(entries)

    raw_module_ast =
      if proxies != [] do
        quote do
          defmodule Raw do
            (unquote_splicing(proxies))
          end
        end
      end

    {asts ++ List.wrap(raw_module_ast), exports}
  end

  @doc """
  Generates public wrappers that call functions in `raw_module` directly.

  Kind-scoped declarations are omitted because they are an implementation
  detail of resource modules rather than part of the public wrapper surface.
  """
  def public_nif_ast_from_decls(decls, raw_module, codec) do
    for nif <- decls, nif.nif_name != nif.wrapper_name do
      {args, arity} = arguments_for(nif)
      name = normalize_function_name(nif.wrapper_name)
      {wrapper_ast(nif, name, args, arity, raw_module, codec), {name, arity}}
    end
    |> Enum.unzip()
  end

  defp wrapper_ast(nif, name, args, arity, raw_module, codec) do
    context = Macro.escape(call_error_context(nif, name, arity))
    raw_args = Enum.map(args, &quote(do: Kinda.unwrap_ref(unquote(&1))))
    call = remote_call_ast(raw_module, name, raw_args)

    quote do
      unquote(typespec_attribute_ast(name, nif.param_typespecs, nif.return_typespec))
      unquote(doc_attribute_ast(nif.doc))

      def unquote(name)(unquote_splicing(args)) do
        unquote(call) |> unquote(codec).normalize()
      rescue
        error in Kinda.CallError ->
          reraise Kinda.CallError.enrich(error, unquote(context), [unquote_splicing(args)]), __STACKTRACE__
      end
    end
  end

  @doc """
  Generates native stubs without a public proxy layer.

  Public declarations use their wrapper name in the raw module. Kind-scoped
  declarations retain their fully-qualified function atoms so each resource
  kind remains unambiguous.
  """
  def raw_nif_ast_from_decls(decls) do
    for nif <- decls do
      {args, arity} = arguments_for(nif)
      name = if nif.nif_name == nif.wrapper_name, do: nif.nif_name, else: normalize_function_name(nif.wrapper_name)

      ast =
        quote do
          @doc false
          def unquote(name)(unquote_splicing(args)), do: :erlang.nif_error(:not_loaded)
        end

      {ast, {name, arity}}
    end
    |> Enum.unzip()
  end

  def type_decls_ast(type_decls) when is_list(type_decls), do: Enum.flat_map(type_decls, &type_decl_ast/1)

  defp normalize_nif_decl(%NIFDecl{nif_name: nil, wrapper_name: wrapper_name} = nif, root_module)
       when not is_nil(wrapper_name), do: %{nif | nif_name: Module.concat(root_module, wrapper_name)}

  defp normalize_nif_decl(%NIFDecl{} = nif, _root_module), do: nif

  defp arguments_for(%NIFDecl{params: params}) when is_list(params),
    do: {Enum.map(params, &Macro.var(&1, __MODULE__)), length(params)}

  defp arguments_for(%NIFDecl{params: params}) when is_integer(params),
    do: {Macro.generate_unique_arguments(params, __MODULE__), params}

  defp normalize_function_name(name) when is_binary(name), do: String.to_atom(name)
  defp normalize_function_name(name) when is_atom(name), do: name

  defp call_error_context(%NIFDecl{} = nif, wrapper_name, arity) do
    argument_names = if is_list(nif.params), do: nif.params, else: []

    argument_types =
      Enum.map(nif.param_ctypes || [], fn
        %{spelling: spelling} -> spelling
        _ -> nil
      end)

    %{function: wrapper_name, arity: arity, argument_names: argument_names, argument_types: argument_types}
  end

  defp remote_call_ast(module, function, args), do: {{:., [], [module, function]}, [], args}

  defp doc_attribute_ast(nil), do: nil

  defp doc_attribute_ast(doc), do: quote(do: @doc(unquote(doc)))

  defp typespec_attribute_ast(_name, params, result) when is_nil(params) or is_nil(result), do: nil

  defp typespec_attribute_ast(name, params, return_type) do
    quote do
      @spec unquote(name)(unquote_splicing(Enum.map(params, &TypeSpecRef.to_quoted/1))) ::
              unquote(TypeSpecRef.to_quoted(return_type))
    end
  end

  defp type_decl_ast(%TypeDecl{name: name, doc: doc, typespec: typespec}),
    do: [
      quote(do: @typedoc(unquote(doc))),
      quote(do: @type(unquote(name)() :: unquote(TypeSpecRef.to_quoted(typespec))))
    ]
end
