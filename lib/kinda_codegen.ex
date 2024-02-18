defmodule Kinda.CodeGen do
  @moduledoc """
  Behavior for customizing your source code generation.
  """

  alias Kinda.CodeGen.{KindDecl}

  defmacro __using__(_) do
    quote do
      @behaviour Kinda.CodeGen
    end
  end

  @callback kinds() :: KindDecl.t()
  def kinds(), do: []
end
