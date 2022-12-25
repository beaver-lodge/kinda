defmodule Kinda.CodeGen.NIFDecl do
  alias Kinda.CodeGen.KindDecl
  @type dirty() :: :io | :cpu | false
  @type t() :: %__MODULE__{
          wrapper_name: nil | String.t(),
          zig_name: nil | String.t(),
          nif_name: nil | String.t(),
          arity: integer(),
          ret: String.t(),
          dirty: dirty()
        }
  defstruct zig_name: nil, nif_name: nil, arity: 0, ret: nil, dirty: false, wrapper_name: nil

  defp arity({:fn, _fn_opts, [name: _name, params: [:...], type: _ret]}), do: 0

  defp arity({:fn, _fn_opts, [name: _name, params: params, type: _ret]}), do: length(params)

  def from_function(
        {:fn, _fn_opts,
         [
           name: name,
           params: _params,
           type: ret
         ]} = f
      ) do
    %__MODULE__{
      wrapper_name: name,
      zig_name: name,
      arity: arity(f),
      ret: ret
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
        arity: a
      }
    end
  end

  # if zig_name is nil this NIF should be registered by other way. For instance, functions of resource kinds.
  def gen(%__MODULE__{zig_name: nil}), do: ""

  def gen(%__MODULE__{zig_name: zig_name, nif_name: nif_name, arity: arity, dirty: dirty}) do
    dirty_flag =
      case dirty do
        :cpu -> "1"
        :io -> "2"
        false -> "0"
      end

    """
    e.ErlNifFunc{.name = "#{nif_name}", .arity = #{arity}, .fptr = #{zig_name}, .flags = #{dirty_flag}},
    """
  end
end
