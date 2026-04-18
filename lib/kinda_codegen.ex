defmodule Kinda.CodeGen do
  @moduledoc """
  Behavior for customizing your source code generation.
  """

  alias Kinda.CodeGen.{KindDecl, NIFDecl, TypeSpecRef}

  defmacro __using__(opts) do
    quote do
      mod = Keyword.fetch!(unquote(opts), :with)
      root = Keyword.fetch!(unquote(opts), :root)
      forward = Keyword.fetch!(unquote(opts), :forward)
      decls = Kinda.CodeGen.nif_decls(mod.kinds(), mod.nifs(), root)
      signature_manifest =
        if function_exported?(mod, :signature_manifest, 0), do: mod.signature_manifest(), else: nil

      {ast, mf} = Kinda.CodeGen.nif_ast_from_decls(decls, root, forward)

      (Kinda.CodeGen.record_types_ast(signature_manifest) ++ ast)
      |> Code.eval_quoted([], __ENV__)

      Module.put_attribute(__MODULE__, :kinda_nif_decls, decls)
      Module.put_attribute(__MODULE__, :kinda_signature_manifest, signature_manifest)

      @doc false
      def __kinda_nif_decls__, do: @kinda_nif_decls

      @doc false
      def __kinda_signature_manifest__, do: @kinda_signature_manifest

      mf
    end
  end

  @type nif_decl_input :: NIFDecl.t() | {atom(), integer()} | {atom(), [atom()]}
  @type signature_manifest :: map() | nil

  @callback kinds() :: [KindDecl.t()]
  @callback nifs() :: [nif_decl_input()]
  @callback signature_manifest() :: signature_manifest()
  @optional_callbacks signature_manifest: 0
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

  def record_types_ast(nil), do: []

  def record_types_ast(%{"records" => records}) when is_list(records) do
    Enum.flat_map(records, &record_type_ast/1)
  end

  defp normalize_nif_decl(%NIFDecl{nif_name: nil, wrapper_name: wrapper_name} = nif, root_module)
       when not is_nil(wrapper_name) do
    %{nif | nif_name: Module.concat(root_module, wrapper_name)}
  end

  defp normalize_nif_decl(%NIFDecl{} = nif, _root_module), do: nif

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

  defp record_type_ast(%{"name" => name, "public_typespec" => public_typespec})
       when is_binary(name) and is_map(public_typespec) do
    type_name = record_type_name(name)
    typespec = TypeSpecRef.from_manifest(public_typespec)

    [
      quote do
        @typedoc unquote("Typed projection for extracted C record #{name}.")
      end,
      quote do
        @type unquote(type_name)() :: unquote(TypeSpecRef.to_quoted(typespec))
      end
    ]
  end

  defp record_type_ast(_record), do: []

  defp record_type_name(record_name) do
    record_name
    |> Macro.underscore()
    |> Kernel.<>("_record")
    |> String.to_atom()
  end
end
