defmodule KindaExample.CodeGen do
  @moduledoc false
  alias Kinda.CodeGen.{KindDecl}
  use Kinda.CodeGen

  @impl true
  def kinds() do
    [
      %KindDecl{
        module_name: KindaExample.NIF.CInt
      }
    ]
  end
end
