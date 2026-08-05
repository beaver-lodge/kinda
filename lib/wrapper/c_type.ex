defmodule Kinda.Wrapper.CType do
  @moduledoc """
  Normalized C type fact extracted from a wrapper surface.
  """

  alias Kinda.CodeGen.TypeSpecRef

  @type kind() ::
          :void
          | :bool
          | :integer
          | :float
          | :pointer
          | :function_pointer
          | :record
          | :enum
          | :unknown

  @type t() :: %__MODULE__{
          spelling: String.t() | nil,
          kind: kind()
        }

  defstruct spelling: nil, kind: :unknown

  @spec from_clang_type(map() | String.t() | nil) :: t() | nil
  def from_clang_type(nil), do: nil

  def from_clang_type(%{} = type_node) do
    case Map.get(type_node, "desugaredQualType") || Map.get(type_node, "qualType") do
      nil -> nil
      type -> from_clang_type(type)
    end
  end

  def from_clang_type(type) when is_binary(type) do
    spelling = normalize(type)
    %__MODULE__{spelling: spelling, kind: classify(spelling)}
  end

  @spec from_function_decl(map()) :: t() | nil
  def from_function_decl(%{} = node) do
    node
    |> Map.get("type", %{})
    |> case do
      %{"qualType" => qual_type} -> qual_type
      %{"desugaredQualType" => qual_type} -> qual_type
      _ -> nil
    end
    |> extract_return_spelling()
    |> from_clang_type()
  end

  @spec to_public_typespec_ref(t() | nil) :: TypeSpecRef.t()
  def to_public_typespec_ref(nil), do: TypeSpecRef.term()
  def to_public_typespec_ref(%__MODULE__{kind: :void}), do: TypeSpecRef.ok()
  def to_public_typespec_ref(%__MODULE__{kind: :bool}), do: TypeSpecRef.boolean()
  def to_public_typespec_ref(%__MODULE__{kind: :integer}), do: TypeSpecRef.integer()
  def to_public_typespec_ref(%__MODULE__{kind: :enum}), do: TypeSpecRef.integer()
  def to_public_typespec_ref(%__MODULE__{kind: :float}), do: TypeSpecRef.float()
  def to_public_typespec_ref(%__MODULE__{}), do: TypeSpecRef.term()

  @spec to_manifest(t() | nil) :: map() | nil
  def to_manifest(nil), do: nil

  def to_manifest(%__MODULE__{spelling: spelling, kind: kind}) do
    %{
      "spelling" => spelling,
      "kind" => Atom.to_string(kind)
    }
  end

  @spec from_manifest(map() | nil) :: t() | nil
  def from_manifest(nil), do: nil

  def from_manifest(%{"spelling" => spelling, "kind" => kind}) when is_binary(kind) do
    %__MODULE__{
      spelling: spelling,
      kind: String.to_existing_atom(kind)
    }
  end

  defp extract_return_spelling(nil), do: nil

  defp extract_return_spelling(qual_type) when is_binary(qual_type) do
    qual_type
    |> normalize()
    |> String.split(" (", parts: 2)
    |> hd()
  end

  defp normalize(type) do
    type
    |> String.replace(~r/\bconst\b/u, "")
    |> String.replace(~r/\bvolatile\b/u, "")
    |> String.replace(~r/\brestrict\b/u, "")
    |> String.replace(~r/\s+/, " ")
    |> String.replace(" *", "*")
    |> String.replace("* ", "*")
    |> String.trim()
  end

  defp classify("void"), do: :void
  defp classify("bool"), do: :bool
  defp classify(type) when type in ~w[float double f32 f64], do: :float

  defp classify(type) do
    cond do
      String.contains?(type, "(*)") or String.contains?(type, "(*") ->
        :function_pointer

      String.contains?(type, "*") ->
        :pointer

      String.starts_with?(type, "enum ") ->
        :enum

      String.starts_with?(type, "struct ") or String.starts_with?(type, "union ") ->
        :record

      integer_spelling?(type) ->
        :integer

      true ->
        :unknown
    end
  end

  defp integer_spelling?(type) do
    cond do
      type in ~w[
        char
        signed char
        unsigned char
        short
        unsigned short
        int
        unsigned int
        long
        unsigned long
        long long
        unsigned long long
        i8
        i16
        i32
        i64
        u8
        u16
        u32
        u64
        isize
        usize
        c_int
        c_uint
        size_t
        ssize_t
        intptr_t
        uintptr_t
        ptrdiff_t
      ] ->
        true

      Regex.match?(~r/^(u?int(8|16|32|64)_t)$/u, type) ->
        true

      true ->
        false
    end
  end
end
