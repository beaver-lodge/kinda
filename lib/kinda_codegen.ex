defmodule Kinda.CodeGen do
  @moduledoc """
  Behavior for customizing your source code generation.
  """

  alias Kinda.CodeGen.{KindDecl, NIFDecl}

  defmacro __using__(opts) do
    quote do
      mod = Keyword.fetch!(unquote(opts), :with)
      root = Keyword.fetch!(unquote(opts), :root)
      forward = Keyword.fetch!(unquote(opts), :forward)
      {ast, mf} = Kinda.CodeGen.nif_ast(mod.kinds(), mod.nifs(), root, forward)
      ast |> Code.eval_quoted([], __ENV__)
      mf
    end
  end

  @type nif_decl_input :: NIFDecl.t() | {atom(), integer()} | {atom(), [atom()]}

  @callback kinds() :: [KindDecl.t()]
  @callback nifs() :: [nif_decl_input()]
  def kinds(), do: []

  def nif_ast(kinds, nifs, root_module, forward_module) do
    # generate stubs for generated NIFs
    extra_kind_nifs =
      kinds
      |> Enum.map(&NIFDecl.from_resource_kind/1)
      |> List.flatten()

    nifs = nifs ++ extra_kind_nifs

    for nif <- nifs do
      nif =
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
            unquote(doc_attribute_ast(nif.doc))

            def unquote(wrapper_name)(unquote_splicing(args_ast)) do
              Kinda.Forwarder.invoke_public_nif(
                unquote(forward_module),
                __MODULE__,
                unquote(nif_name),
                [unquote_splicing(args_ast)]
              )
            end
          end
        end

      quote do
        unquote(doc_attribute_ast(if(nif_name == wrapper_name, do: nif.doc, else: false)))

        def unquote(nif_name)(unquote_splicing(args_ast)),
          do: :erlang.nif_error(:not_loaded)

        unquote(wrapper_ast)
      end
      |> then(&{&1, {nif_name, arity}})
    end
    |> Enum.unzip()
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
end
