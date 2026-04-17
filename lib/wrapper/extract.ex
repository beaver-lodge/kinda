defmodule Kinda.Wrapper.Extract do
  @moduledoc """
  Extracts a normalized wrapper manifest from a Clang AST tree.
  """

  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Manifest

  @spec from_clang_ast(map() | list()) :: Manifest.t()
  def from_clang_ast(ast) do
    %Manifest{
      functions:
        ast
        |> collect_functions()
        |> Enum.sort_by(& &1.name)
    }
  end

  defp collect_functions(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &collect_functions/1)
  end

  defp collect_functions(%{"kind" => "FunctionDecl", "name" => name} = node) do
    params =
      node
      |> Map.get("inner", [])
      |> Enum.with_index()
      |> Enum.filter(fn {elem, _index} -> Map.get(elem, "kind") == "ParmVarDecl" end)
      |> Enum.map(fn {elem, index} -> Map.get(elem, "name", "param_#{index}") end)

    [%Function{name: name, params: params, arity: length(params)} | collect_children(node)]
  end

  defp collect_functions(node) when is_map(node), do: collect_children(node)
  defp collect_functions(_node), do: []

  defp collect_children(node), do: node |> Map.get("inner", []) |> collect_functions()
end
