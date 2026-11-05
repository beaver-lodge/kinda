defmodule Kinda.CodeGen.NIFDecl do
  @moduledoc """
  A generated NIF declaration.

  Describes a NIF's wrapper and NIF names, parameters (as an arity or a list
  of names), C types, typespecs and dirty scheduler flag, and round-trips to
  and from the JSON-compatible manifest format. `from_resource_kind/1` expands
  the standard NIF functions a resource kind is expected to provide.
  """

  alias Kinda.CodeGen.{KindDecl, TypeSpecRef}
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
  defstruct ~w(nif_name wrapper_name params doc param_ctypes return_ctype param_typespecs return_typespec)a ++
              [arity: 0, dirty: false]

  @spec from_manifest(map()) :: t()
  def from_manifest(%{} = manifest),
    do: %__MODULE__{
      wrapper_name: denormalize_name(Map.get(manifest, "wrapper_name")),
      nif_name: denormalize_name(Map.get(manifest, "nif_name")),
      params: denormalize_params(Map.get(manifest, "params")),
      doc: Map.get(manifest, "doc"),
      param_ctypes: Enum.map(Map.get(manifest, "param_ctypes", []), &CType.from_manifest/1),
      return_ctype: CType.from_manifest(Map.get(manifest, "return_ctype")),
      param_typespecs: denormalize_typespecs(Map.get(manifest, "param_typespecs")),
      return_typespec: denormalize_typespec(Map.get(manifest, "return_typespec")),
      dirty: denormalize_dirty(Map.get(manifest, "dirty", false))
    }

  @spec to_manifest(t()) :: map()
  def to_manifest(%__MODULE__{} = nif),
    do: %{
      "wrapper_name" => normalize_name(nif.wrapper_name),
      "nif_name" => normalize_name(nif.nif_name),
      "params" => normalize_params(nif.params),
      "doc" => nif.doc,
      "param_ctypes" => Enum.map(nif.param_ctypes || [], &CType.to_manifest/1),
      "return_ctype" => CType.to_manifest(nif.return_ctype),
      "param_typespecs" => normalize_typespecs(nif.param_typespecs),
      "return_typespec" => if(nif.return_typespec, do: TypeSpecRef.to_manifest(nif.return_typespec)),
      "dirty" => normalize_dirty(nif.dirty)
    }

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
      %__MODULE__{nif_name: Module.concat(module_name, f), wrapper_name: Module.concat(module_name, f), params: a}
    end
  end

  defp normalize_name(nil), do: nil
  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name) when is_binary(name), do: name

  defp normalize_params(params) when is_integer(params), do: params
  defp normalize_params(params) when is_list(params), do: Enum.map(params, &normalize_name/1)

  defp normalize_dirty(false), do: false
  defp normalize_dirty(dirty) when is_atom(dirty), do: Atom.to_string(dirty)

  defp normalize_typespecs(types) when is_list(types), do: Enum.map(types, &TypeSpecRef.to_manifest/1)
  defp normalize_typespecs(_types), do: nil

  defp denormalize_name(nil), do: nil
  defp denormalize_name(name) when is_binary(name), do: String.to_atom(name)

  defp denormalize_params(params) when is_integer(params), do: params
  defp denormalize_params(params) when is_list(params), do: Enum.map(params, &denormalize_name/1)
  defp denormalize_params(nil), do: nil

  defp denormalize_typespecs(nil), do: nil

  defp denormalize_typespecs(typespecs) when is_list(typespecs), do: Enum.map(typespecs, &TypeSpecRef.from_manifest/1)

  defp denormalize_typespec(nil), do: nil
  defp denormalize_typespec(typespec), do: TypeSpecRef.from_manifest(typespec)

  defp denormalize_dirty(false), do: false
  defp denormalize_dirty(nil), do: false
  defp denormalize_dirty(dirty) when is_binary(dirty), do: String.to_atom(dirty)
end
