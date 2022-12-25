defmodule Kinda.CodeGen do
  @moduledoc """
  Behavior for customizing your source code generation.
  """

  alias Kinda.CodeGen.{KindDecl, NIFDecl}

  defmacro __using__(_) do
    quote do
      @behaviour Kinda.CodeGen
    end
  end

  @callback type_gen(atom(), String.t()) :: {:ok, KindDecl.t()} | :skip

  @callback nif_gen(any()) :: NIFDecl.t()
  def nif_gen(f), do: NIFDecl.from_function(f)

  @callback kinds() :: KindDecl.t()
  def kinds(), do: []
end
