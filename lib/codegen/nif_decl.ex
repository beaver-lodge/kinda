defmodule Kinda.CodeGen.NIFDecl do
  @moduledoc """
  A generated NIF declaration.

  Describes a NIF's wrapper and NIF names, parameters (as an arity or a list
  of names), C types, typespecs and dirty scheduler flag, and round-trips to
  and from the JSON-compatible manifest format. `from_resource_kind/1` expands
  the standard NIF functions a resource kind is expected to provide.
  """

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

  @spec from_manifest(map()) :: t()
  def from_manifest(%{} = manifest) do
    %__MODULE__{
      wrapper_name: denormalize_name(Map.get(manifest, "wrapper_name")),
      nif_name: denormalize_name(Map.get(manifest, "nif_name")),
      params: denormalize_params(Map.get(manifest, "params")),
      doc: Map.get(manifest, "doc"),
      param_ctypes: Enum.map(Map.get(manifest, "param_ctypes", []), &denormalize_ctype/1),
      return_ctype: denormalize_ctype(Map.get(manifest, "return_ctype")),
      param_typespecs: denormalize_typespecs(Map.get(manifest, "param_typespecs")),
      return_typespec: denormalize_typespec(Map.get(manifest, "return_typespec")),
      dirty: denormalize_dirty(Map.get(manifest, "dirty", false))
    }
  end

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

  defp denormalize_name(nil), do: nil
  defp denormalize_name(name) when is_binary(name), do: String.to_atom(name)

  defp denormalize_params(params) when is_integer(params), do: params
  defp denormalize_params(params) when is_list(params), do: Enum.map(params, &denormalize_name/1)
  defp denormalize_params(nil), do: nil

  defp denormalize_typespecs(nil), do: nil

  defp denormalize_typespecs(typespecs) when is_list(typespecs),
    do: Enum.map(typespecs, &TypeSpecRef.from_manifest/1)

  defp denormalize_typespec(nil), do: nil
  defp denormalize_typespec(typespec), do: TypeSpecRef.from_manifest(typespec)

  defp denormalize_dirty(false), do: false
  defp denormalize_dirty(nil), do: false
  defp denormalize_dirty(dirty) when is_binary(dirty), do: String.to_atom(dirty)

  defp denormalize_ctype(nil), do: nil

  defp denormalize_ctype(%{"spelling" => spelling, "kind" => kind}) when is_binary(kind) do
    struct(CType, spelling: spelling, kind: String.to_existing_atom(kind))
  end
end
