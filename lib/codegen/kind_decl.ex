defmodule Kinda.CodeGen.KindDecl do
  require Logger

  @primitive_types for t <- ~w{
    bool
    c_int
    c_uint
    f32
    f64
    i16
    i32
    i64
    i8
    isize
    u16
    u32
    u64
    u8
    usize
  },
                       do: String.to_atom(t)

  @opaque_ptr {:optional_type, {:ref, [:*, :anyopaque]}}
  @opaque_array {:optional_type, {:ref, [:*, :const, :anyopaque]}}

  def primitive_types do
    @primitive_types
  end

  @primitive_types_set MapSet.new(@primitive_types)
  def is_primitive_type?(t) do
    MapSet.member?(@primitive_types_set, t)
  end

  def is_opaque_ptr?(t) do
    t == @opaque_ptr or t == @opaque_array
  end

  #
  @type t() :: %__MODULE__{
          kind_name: atom(),
          zig_t: String.t(),
          module_name: atom(),
          fields: list(atom()),
          kind_functions: list({atom(), integer()})
        }
  defstruct kind_name: nil, zig_t: nil, module_name: nil, fields: [], kind_functions: []

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

  defp module_basename(@opaque_ptr) do
    :OpaquePtr
  end

  defp module_basename(@opaque_array) do
    :OpaqueArray
  end

  # zig 0.9
  defp module_basename("?fn(" <> _ = fn_name) do
    raise "need module name for function type: #{fn_name}"
  end

  # zig 0.10
  defp module_basename("?*const fn(" <> _ = fn_name) do
    raise "need module name for function type: #{fn_name}"
  end

  defp module_basename(type) when is_atom(type) do
    type |> Atom.to_string() |> module_basename()
  end

  defp module_basename(type) when is_binary(type) do
    type |> Macro.camelize() |> String.to_atom()
  end

  def default(root_module, type) when is_atom(type) or type in [@opaque_ptr, @opaque_array] do
    {:ok,
     %__MODULE__{zig_t: type, module_name: Module.concat(root_module, module_basename(type))}}
  end

  def default(root_module, type) do
    Logger.error(
      "Code generation for #{inspect(root_module)} not implemented for type:\n#{inspect(type, pretty: true)}"
    )

    raise "Code gen not implemented"
  end

  defp dump_zig_type(@opaque_ptr) do
    {:ok, "?*anyopaque"}
  end

  defp dump_zig_type(@opaque_array) do
    {:ok, "?*const anyopaque"}
  end

  defp dump_zig_type(t) when t in @primitive_types do
    {:ok, Atom.to_string(t)}
  end

  defp dump_zig_type(t) when is_atom(t) do
    {:ok, "c." <> Atom.to_string(t)}
  end

  defp dump_zig_type(t) when is_atom(t) do
    {:ok, "c." <> Atom.to_string(t)}
  end

  defp dump_zig_type(_t) do
    :error
  end

  defp zig_type(%__MODULE__{
         zig_t: zig_t,
         kind_name: kind_name
       }) do
    with {:ok, t} <- dump_zig_type(zig_t) do
      t
    else
      _ ->
        "c.#{kind_name}"
    end
  end

  def gen_resource_kind(%__MODULE__{module_name: module_name, kind_name: kind_name} = k) do
    """
    pub const #{kind_name} = kinda.ResourceKind(#{zig_type(k)}, "#{module_name}");
    """
  end
end
