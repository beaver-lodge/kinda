defmodule Kinda.CodeGen.Type do
  @type t() :: %__MODULE__{
          zig_t: String.t(),
          module_name: atom(),
          kind_name: atom(),
          fields: list(atom()),
          kind_functions: list({atom(), integer()})
        }
  defstruct zig_t: nil,
            module_name: nil,
            kind_name: nil,
            fields: [],
            kind_functions: []

  def array_type_name(type) do
    "[*c]const " <> type
  end

  def ptr_type_name(type) do
    "[*c]" <> type
  end

  defp module_basename(%__MODULE__{module_name: module_name}) do
    module_name |> Module.split() |> List.last() |> String.to_atom()
  end

  defp module_basename("c.struct_" <> struct_name) do
    struct_name |> String.to_atom()
  end

  defp module_basename("isize") do
    :ISize
  end

  defp module_basename("usize") do
    :USize
  end

  defp module_basename("c_int") do
    :CInt
  end

  defp module_basename("c_uint") do
    :CUInt
  end

  defp module_basename("[*c]const u8") do
    :CString
  end

  defp module_basename("?*anyopaque") do
    :OpaquePtr
  end

  defp module_basename("?*const anyopaque") do
    :OpaqueArray
  end

  defp module_basename("?fn(" <> _ = fn_name) do
    raise "need module name for function type: #{fn_name}"
  end

  defp module_basename(type) when is_binary(type) do
    type |> String.capitalize() |> String.to_atom()
  end

  def default(root_module, type) when is_binary(type) do
    {:ok,
     %__MODULE__{zig_t: type, module_name: Module.concat(root_module, module_basename(type))}}
  end

  def gen_resource_kind(%__MODULE__{module_name: module_name, zig_t: zig_t, kind_name: kind_name}) do
    """
    pub const #{kind_name} = kinda.ResourceKind(#{zig_t}, "#{module_name}");
    """
  end
end
