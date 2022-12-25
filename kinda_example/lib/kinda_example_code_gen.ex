defmodule KindaExample.CodeGen do
  @moduledoc false
  alias Kinda.CodeGen.{KindDecl, NIFDecl}
  use Kinda.CodeGen

  @impl true
  def kinds() do
    []
  end

  @impl true
  def type_gen(root_module, type) do
    KindDecl.default(root_module, type)
  end

  def nif_gen(f) do
    NIFDecl.from_function(f)
  end
end
