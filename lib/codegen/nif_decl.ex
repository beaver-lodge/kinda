defmodule Kinda.CodeGen.NIFDecl do
  alias Kinda.CodeGen.KindDecl
  @type dirty() :: :io | :cpu | false
  @type t() :: %__MODULE__{
          wrapper_name: nil | String.t(),
          nif_name: nil | String.t(),
          arity: integer()
        }
  defstruct nif_name: nil, arity: 0, wrapper_name: nil

  # TODO: make this extensible
  def from_resource_kind(%KindDecl{module_name: module_name, kind_functions: kind_functions}) do
    for {f, a} <-
          [
            ptr: 1,
            ptr_to_opaque: 1,
            opaque_ptr: 1,
            array: 1,
            mut_array: 1,
            primitive: 1,
            make: 1,
            dump: 1,
            make_from_opaque_ptr: 2,
            array_as_opaque: 1
          ] ++ kind_functions do
      %__MODULE__{
        nif_name: Module.concat(module_name, f),
        wrapper_name: Module.concat(module_name, f),
        arity: a
      }
    end
  end
end
