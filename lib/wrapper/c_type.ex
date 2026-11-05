defmodule Kinda.Wrapper.CType do
  @moduledoc """
  Normalized C type fact extracted from a wrapper surface.
  """

  alias Kinda.CodeGen.TypeSpecRef

  @type kind() :: :void | :bool | :integer | :float | :pointer | :function_pointer | :record | :enum | :unknown

  @type t() :: %__MODULE__{spelling: String.t() | nil, kind: kind()}

  defstruct spelling: nil, kind: :unknown

  @spec from_clang_type(map() | String.t() | nil) :: t() | nil
  def from_clang_type(nil), do: nil

  def from_clang_type(%{} = node), do: from_clang_type(Map.get(node, "desugaredQualType") || Map.get(node, "qualType"))

  def from_clang_type(type) when is_binary(type) do
    spelling = normalize(type)
    %__MODULE__{spelling: spelling, kind: classify(spelling)}
  end

  @spec from_function_decl(map()) :: t() | nil
  def from_function_decl(%{"type" => type}) when is_map(type) do
    type
    |> Map.get("qualType", Map.get(type, "desugaredQualType"))
    |> extract_return_spelling()
    |> from_clang_type()
  end

  def from_function_decl(%{}), do: nil

  @spec to_public_typespec_ref(t() | nil) :: TypeSpecRef.t()
  def to_public_typespec_ref(nil), do: :term

  def to_public_typespec_ref(%__MODULE__{kind: kind}),
    do: Map.get(%{void: :ok, bool: :boolean, integer: :integer, enum: :integer, float: :float}, kind, :term)

  @spec to_manifest(t() | nil) :: map() | nil
  def to_manifest(nil), do: nil

  def to_manifest(%{spelling: spelling, kind: kind}), do: %{"spelling" => spelling, "kind" => Atom.to_string(kind)}

  @spec from_manifest(map() | nil) :: t() | nil
  def from_manifest(nil), do: nil

  def from_manifest(%{"spelling" => spelling, "kind" => kind}) when is_binary(kind),
    do: %__MODULE__{spelling: spelling, kind: String.to_existing_atom(kind)}

  defp extract_return_spelling(nil), do: nil

  defp extract_return_spelling(qual_type) when is_binary(qual_type),
    do: qual_type |> normalize() |> String.split(" (", parts: 2) |> hd()

  defp normalize(type) do
    type
    |> String.replace(~r/\b(const|volatile|restrict)\b/u, "")
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
      String.contains?(type, "(*)") or String.contains?(type, "(*") -> :function_pointer
      String.contains?(type, "*") -> :pointer
      String.starts_with?(type, "enum ") -> :enum
      String.starts_with?(type, "struct ") or String.starts_with?(type, "union ") -> :record
      integer_spelling?(type) -> :integer
      true -> :unknown
    end
  end

  defp integer_spelling?(type),
    do:
      type in ~w[char signed char unsigned char short unsigned short int unsigned int long unsigned long long long
      unsigned long long i8 i16 i32 i64 u8 u16 u32 u64 isize usize c_int c_uint size_t ssize_t intptr_t uintptr_t ptrdiff_t] or
        Regex.match?(~r/^(u?int(8|16|32|64)_t)$/u, type)
end
