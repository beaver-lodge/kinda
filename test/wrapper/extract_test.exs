defmodule Kinda.Wrapper.ExtractTest do
  use ExUnit.Case, async: true

  alias Kinda.Wrapper.Extract
  alias Kinda.Wrapper.Function
  alias Kinda.Wrapper.Manifest

  test "extracts a normalized manifest from clang ast" do
    ast = %{
      "kind" => "TranslationUnitDecl",
      "inner" => [
        %{
          "kind" => "FunctionDecl",
          "name" => "mlirFoo",
          "inner" => [
            %{"kind" => "ParmVarDecl", "name" => "ctx"},
            %{"kind" => "ParmVarDecl"}
          ]
        },
        %{
          "kind" => "NamespaceDecl",
          "inner" => [
            %{
              "kind" => "FunctionDecl",
              "name" => "mlirBar",
              "inner" => []
            }
          ]
        }
      ]
    }

    assert Extract.from_clang_ast(ast) == %Manifest{
             functions: [
               %Function{name: "mlirBar", params: [], arity: 0},
               %Function{name: "mlirFoo", params: ["ctx", "param_1"], arity: 2}
             ]
           }
  end
end
