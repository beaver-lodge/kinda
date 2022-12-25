defmodule Kinda do
  alias Kinda.CodeGen.KindDecl
  require Logger

  @moduledoc """
  Documentation for `Kinda`.
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

  def module_name(zig_t, forward_module, zig_t_module_map) do
    if Kinda.ZigAST.is_array?(zig_t) do
      forward_module |> Module.concat("Array")
    else
      if Kinda.ZigAST.is_ptr?(zig_t) do
        forward_module |> Module.concat("Ptr")
      else
        zig_t_module_map |> Map.fetch!(zig_t)
      end
    end
  end

  def zig_sources() do
    __DIR__ |> Path.join("..") |> Path.join("zig-src") |> Path.join("*.zig") |> Path.wildcard()
  end
end
