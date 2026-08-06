defmodule Kinda do
  @moduledoc """
  Kinda binds C libraries to the BEAM with Zig.

  It generates NIF wrappers from Clang-extracted C signatures, compiles them
  with `elixir_make`, and provides the declaration, wrapper-extraction and
  precompilation surfaces used by projects such as
  [Beaver](https://github.com/beaver-lodge/beaver).

  See the [README](readme.html) for an overview. The main API surfaces are:

    * `Kinda.Declaration` - the stable entry point for Kinda's declaration contract
    * `Kinda.CodeGen` - code generation and declaration IR
    * `Kinda.CallbackRuntime` - the common BEAM callback/reply boundary
    * `Kinda.Precompiler` - precompiled NIF support for `elixir_make`
  """

  def unwrap_ref(%{ref: ref}) do
    ref
  end

  def unwrap_ref(arguments) when is_list(arguments) do
    Enum.map(arguments, &unwrap_ref/1)
  end

  def unwrap_ref(term) do
    term
  end
end
