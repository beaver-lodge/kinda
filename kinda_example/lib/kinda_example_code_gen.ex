defmodule KindaExample.CodeGen do
  @moduledoc false
  alias Kinda.CodeGen.{Type, NIF, Function}
  use Kinda.CodeGen

  @impl true
  def kinds() do
    []
  end

  @impl true
  def filter_functions(fns) do
    fns
  end

  @impl true
  def type_gen(root_module, type) do
    Type.default(root_module, type)
  end

  def nif_gen(f) do
    NIF.from_function(f)
  end
end
