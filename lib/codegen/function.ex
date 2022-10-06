defmodule Kinda.CodeGen.Function do
  @type t() :: %__MODULE__{
          name: String.t(),
          args: list(),
          ret: String.t()
        }
  defstruct name: nil, args: [], ret: nil

  def process_type("struct_" <> _ = arg) do
    "c.#{arg}"
  end

  def process_type(arg) do
    String.replace(arg, ~r/\.cimport.+?\./, "c.")
  end

  def nif_func_name(func) do
    "kinda_nif_#{func}"
  end
end
