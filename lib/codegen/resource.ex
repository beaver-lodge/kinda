defmodule Kinda.CodeGen.Resource do
  alias Kinda.CodeGen.KindDecl

  def resource_type_struct(
        {:cptr,
         %Zig.Parser.PointerOptions{align: nil, const: true, volatile: false, allowzero: false},
         [type: type]},
        %{} = resource_kind_map
      ) do
    mod = Map.fetch!(resource_kind_map, type)
    "#{mod}.Array"
  end

  def resource_type_struct(
        {:cptr,
         %Zig.Parser.PointerOptions{align: nil, const: false, volatile: false, allowzero: false},
         [type: type]},
        %{} = resource_kind_map
      ) do
    mod = Map.fetch!(resource_kind_map, type)
    "#{mod}.Ptr"
  end

  def resource_type_struct(type, %{} = resource_kind_map) do
    mod = Map.fetch!(resource_kind_map, type)
    "#{mod}"
  end

  def resource_type_resource_kind(type, %{} = resource_kind_map) do
    resource_type_struct(type, resource_kind_map) <> ".resource"
  end

  def resource_type_var(type, %{} = resource_kind_map) do
    resource_type_resource_kind(type, resource_kind_map) <> ".t"
  end

  def resource_open(%KindDecl{kind_name: kind_name})
      when kind_name in ~w{USize OpaquePtr OpaqueArray} do
    """
    #{kind_name}.open_all(env);
    kinda.aliasKind(#{kind_name}, kinda.Internal.#{kind_name});
    """
  end

  def resource_open(%KindDecl{kind_name: kind_name}) do
    """
    #{kind_name}.open_all(env);
    """
  end
end
