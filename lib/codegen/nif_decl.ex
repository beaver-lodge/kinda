defmodule Kinda.CodeGen.NIFDecl do
  alias Kinda.CodeGen.KindDecl
  alias Kinda.CodeGen.TypeSpecRef
  alias Kinda.Wrapper.CType
  @type dirty() :: :dirty_io | :dirty_cpu | false
  @type name() :: nil | String.t() | atom()
  @type t() :: %__MODULE__{
          wrapper_name: name(),
          nif_name: name(),
          params: [String.t() | atom()] | integer(),
          doc: String.t() | nil,
          param_ctypes: [CType.t() | nil] | nil,
          return_ctype: CType.t() | nil,
          param_typespecs: [TypeSpecRef.t()] | nil,
          return_typespec: TypeSpecRef.t() | nil,
          dirty: dirty()
        }
  defstruct nif_name: nil,
            arity: 0,
            wrapper_name: nil,
            params: nil,
            doc: nil,
            param_ctypes: nil,
            return_ctype: nil,
            param_typespecs: nil,
            return_typespec: nil,
            dirty: false

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
        params: a
      }
    end
  end
end
