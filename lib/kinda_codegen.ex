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

      Kinda.CodeGen.nif_ast(mod.kinds(), mod.nifs(), root, forward)
      |> then(&Module.eval_quoted(__MODULE__, &1))
    end
  end

  @callback kinds() :: KindDecl.t()
  @callback nifs() :: [{atom(), integer()}]
  def kinds(), do: []

  def nif_ast(kinds, nifs, root_module, forward_module) do
    # generate stubs for generated NIFs
    extra_kind_nifs =
      kinds
      |> Enum.map(&NIFDecl.from_resource_kind/1)
      |> List.flatten()

    for nif <- nifs ++ extra_kind_nifs do
      nif =
        case nif do
          {wrapper_name, arity} when is_atom(wrapper_name) and is_integer(arity) ->
            %NIFDecl{
              wrapper_name: wrapper_name,
              nif_name: Module.concat(root_module, wrapper_name),
              arity: arity
            }

          %NIFDecl{} ->
            nif
        end

      args_ast = Macro.generate_unique_arguments(nif.arity, __MODULE__)

      %NIFDecl{wrapper_name: wrapper_name, nif_name: nif_name} = nif

      wrapper_name =
        if is_bitstring(wrapper_name) do
          String.to_atom(wrapper_name)
        else
          wrapper_name
        end

      quote do
        @doc false
        def unquote(nif_name)(unquote_splicing(args_ast)),
          do:
            raise(
              "NIF for resource kind is not implemented, or failed to load NIF library. Function: :\"#{unquote(nif_name)}\"/#{unquote(nif.arity)}"
            )

        def unquote(wrapper_name)(unquote_splicing(args_ast)) do
          refs = Kinda.unwrap_ref([unquote_splicing(args_ast)])
          ret = apply(__MODULE__, unquote(nif_name), refs)
          unquote(forward_module).check!(ret)
        end
      end
    end
    |> List.flatten()
  end
end
