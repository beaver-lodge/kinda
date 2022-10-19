defmodule Kinda.CodeGen do
  @moduledoc """
  Behavior for customizing your source code generation.
  """

  defmacro __using__(_) do
    quote do
      @behaviour Kinda.CodeGen
    end
  end

  @callback filter_functions(list(Kinda.CodeGen.Function.t())) :: list(Kinda.CodeGen.Function.t())
  def filter_functions(funcs), do: funcs

  @callback type_gen(atom(), String.t()) :: {:ok, Kinda.CodeGen.Type.t()} | :skip

  @callback nif_gen(Kinda.CodeGen.Function.t()) :: Kinda.CodeGen.NIF.t()
  def nif_gen(f), do: Kinda.CodeGen.NIF.from_function(f)

  @callback kinds() :: Kinda.CodeGen.Type.t()
  def kinds(), do: []
end
