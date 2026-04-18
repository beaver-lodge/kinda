defmodule Kinda.CodeGenTest do
  use ExUnit.Case, async: true

  alias Kinda.CodeGen
  alias Kinda.CodeGen.NIFDecl

  defmodule Forward do
    def check!(value), do: value
  end

  test "emits docs on generated public wrappers" do
    {ast, _exports} =
      CodeGen.nif_ast(
        [],
        [
          %NIFDecl{
            wrapper_name: :mlirFoo,
            params: [:ctx],
            doc: "Creates foo.\n\nParameters:\n- `ctx`: Context value."
          }
        ],
        Module.concat(__MODULE__, GeneratedDocs),
        Forward
      )

    ast_string = ast |> then(&{:__block__, [], &1}) |> Macro.to_string()

    assert ast_string =~ ~s(@doc "Creates foo.)
    assert ast_string =~ "defmodule Raw"
    assert ast_string =~ "def mlirFoo(ctx)"
    assert ast_string =~ "GeneratedDocs.Raw"
    assert ast_string =~ "Kinda.Forwarder.invoke_public_nif"
  end

  test "emits raw companion entries for kind-scoped generated functions" do
    {ast, _exports} =
      CodeGen.nif_ast(
        [%Kinda.CodeGen.KindDecl{module_name: Module.concat(__MODULE__, Kind)}],
        [],
        Module.concat(__MODULE__, GeneratedKinds),
        Forward
      )

    ast_string = ast |> then(&{:__block__, [], &1}) |> Macro.to_string()

    assert ast_string =~ "defmodule Raw"
    assert ast_string =~ ~s(def Elixir.Kinda.CodeGenTest.Kind.make)
    assert ast_string =~ ~s(apply(Kinda.CodeGenTest.GeneratedKinds)
  end
end
