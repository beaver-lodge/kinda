defmodule Kinda.CodecTest do
  use ExUnit.Case, async: true

  defmodule RawNIF do
    def unquote(Module.concat(Kinda.CodecTest.RawKind, :make))(value), do: {:ok, value}
  end

  defmodule Codec do
    use Kinda.Codec

    @impl true
    def normalize({:ok, value}), do: value
    def normalize(value), do: Kinda.Codec.normalize(value)
  end

  defmodule RawKind do
    use Kinda.ResourceKind, raw_module: Kinda.CodecTest.RawNIF, codec: Kinda.CodecTest.Codec
  end

  defmodule DecodedKind do
    defstruct [:ref]
  end

  test "resource kinds call their concrete raw make entrypoint" do
    assert %RawKind{ref: 7} = RawKind.make(7)
  end

  test "normalize/1 wraps decoded kind tuples" do
    ref = make_ref()
    assert %DecodedKind{ref: ^ref} = Kinda.Codec.normalize({:kind, DecodedKind, ref})
  end

  test "normalize/1 preserves metadata alongside wrapped kinds" do
    ref = make_ref()

    assert {%DecodedKind{ref: ^ref}, :meta} =
             Kinda.Codec.normalize({{:kind, DecodedKind, ref}, :meta})
  end

  test "normalize/1 leaves plain values unchanged" do
    assert Kinda.Codec.normalize(42) == 42
  end

  test "normalize/1 raises Kinda.CallError for string errors" do
    error =
      assert_raise Kinda.CallError, fn ->
        Kinda.Codec.normalize({:error, "boom"})
      end

    assert Exception.message(error) =~ "boom"
  end

  test "normalize/1 re-raises exception payloads" do
    assert_raise RuntimeError, "oops", fn ->
      Kinda.Codec.normalize({:error, %RuntimeError{message: "oops"}})
    end
  end
end
