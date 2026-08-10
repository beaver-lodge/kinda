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

  test "CallError formats structured argument diagnostics" do
    error = %Kinda.CallError{
      message: "Fail to fetch argument #2",
      reason: :argument_decode_failed,
      phase: :argument_decode,
      function: "raw_add",
      arity: 2,
      argument_index: 2,
      expected: "c_int",
      native_error: "Function clause error"
    }

    enriched =
      Kinda.CallError.enrich(
        error,
        %{
          function: :add,
          arity: 2,
          argument_names: [:lhs, :rhs],
          argument_types: ["int", "int"]
        },
        [1, "2"]
      )

    assert enriched.argument_name == :rhs
    assert enriched.actual == "binary"
    assert enriched.expected == "int"

    assert Exception.message(enriched) ==
             "add/2 rejected argument #2 (rhs): expected int, got binary"

    refute Exception.message(enriched) =~ "KINDA_DUMP_STACK_TRACE"
  end

  test "CallError only suggests a native trace for internal failures" do
    error = %Kinda.CallError{
      message: "OutOfMemory",
      reason: :native_error,
      phase: :native,
      function: "allocate",
      arity: 1,
      native_error: "OutOfMemory"
    }

    assert Exception.message(error) =~ "allocate/1 failed during native"
    assert Exception.message(error) =~ "KINDA_DUMP_STACK_TRACE"
  end

  test "normalize/1 re-raises exception payloads" do
    assert_raise RuntimeError, "oops", fn ->
      Kinda.Codec.normalize({:error, %RuntimeError{message: "oops"}})
    end
  end
end
