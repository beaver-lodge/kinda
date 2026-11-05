defmodule Kinda.CodeGen.KindDecl do
  @moduledoc """
  An explicit resource kind declaration used by generated NIF modules.

  The consumer supplies the resource module and any extra NIF functions.
  """

  @type t() :: %__MODULE__{module_name: module(), kind_functions: [{atom(), non_neg_integer()}]}
  defstruct module_name: nil, kind_functions: []
end
