defmodule KindaExample.CodeGen do
  @moduledoc false
  alias Kinda.CodeGen.{KindDecl}
  @behaviour Kinda.CodeGen
  @impl true
  def kinds() do
    [
      %KindDecl{
        module_name: KindaExample.NIF.CInt
      }
    ]
  end

  @impl true
  def nifs() do
    [
      kinda_example_add: 2
    ]
  end
end
