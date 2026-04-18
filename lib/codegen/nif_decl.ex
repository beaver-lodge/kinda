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

  @spec to_manifest(t()) :: map()
  def to_manifest(%__MODULE__{} = nif_decl) do
    %{
      "wrapper_name" => normalize_name(nif_decl.wrapper_name),
      "nif_name" => normalize_name(nif_decl.nif_name),
      "params" => normalize_params(nif_decl.params),
      "doc" => nif_decl.doc,
      "param_ctypes" => Enum.map(nif_decl.param_ctypes || [], &normalize_ctype/1),
      "return_ctype" => normalize_ctype(nif_decl.return_ctype),
      "param_typespecs" =>
        if is_list(nif_decl.param_typespecs) do
          Enum.map(nif_decl.param_typespecs, &TypeSpecRef.to_manifest/1)
        else
          nil
        end,
      "return_typespec" =>
        if nif_decl.return_typespec do
          TypeSpecRef.to_manifest(nif_decl.return_typespec)
        else
          nil
        end,
      "dirty" => normalize_dirty(nif_decl.dirty)
    }
  end

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

  defp normalize_name(nil), do: nil
  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name) when is_binary(name), do: name

  defp normalize_params(params) when is_integer(params), do: params
  defp normalize_params(params) when is_list(params), do: Enum.map(params, &normalize_name/1)

  defp normalize_dirty(false), do: false
  defp normalize_dirty(dirty) when is_atom(dirty), do: Atom.to_string(dirty)

  defp normalize_ctype(nil), do: nil

  defp normalize_ctype(%{spelling: spelling, kind: kind}) do
    %{
      "spelling" => spelling,
      "kind" => Atom.to_string(kind)
    }
  end
end
