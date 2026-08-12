defmodule KindaExample.CodeGen do
  @moduledoc false
  alias Kinda.CodeGen.{DeclarationManifest, KindDecl, NIFDecl}
  @behaviour Kinda.CodeGen
  @impl true
  def kinds do
    [
      %KindDecl{
        module_name: KindaExample.NIF.CInt
      },
      %KindDecl{
        module_name: KindaExample.NIF.StrInt
      }
    ]
  end

  @impl true
  def declaration_manifest do
    DeclarationManifest.build([
      %NIFDecl{
        wrapper_name: :kinda_example_add,
        params: [:lhs, :rhs]
      },
      %NIFDecl{
        wrapper_name: :kinda_example_sum_19,
        params: Enum.map(1..19, &String.to_atom("value_#{&1}"))
      }
    ])
  end
end
