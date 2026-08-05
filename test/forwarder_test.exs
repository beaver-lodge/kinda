defmodule Kinda.ForwarderTest do
  use ExUnit.Case, async: true

  defmodule Runtime do
    use Kinda.Forwarder, nif_module: Kinda.ForwarderTest.FakeNIF
  end

  defmodule RawKind do
    use Kinda.ResourceKind, forward_module: Kinda.ForwarderTest.Runtime
  end

  defmodule DecodedKind do
    defstruct [:ref]
  end

  defmodule FakeNIF do
    def unquote(Module.concat(Kinda.ForwarderTest.RawKind, "make"))(_value) do
      raise "root kind raw stub should not be called directly"
    end

    def unquote(Module.concat(Kinda.ForwarderTest.DecodedKind, :wrap))() do
      raise "root raw stub should not be called directly"
    end

    def unquote(Module.concat(Kinda.ForwarderTest.DecodedKind, :primitive))(_ref) do
      raise "root primitive raw stub should not be called directly"
    end

    defmodule Raw do
      def unquote(Module.concat(Kinda.ForwarderTest.RawKind, "make"))(value), do: value

      def unquote(Module.concat(Kinda.ForwarderTest.DecodedKind, :wrap))() do
        {:kind, Kinda.ForwarderTest.DecodedKind, make_ref()}
      end

      def unquote(Module.concat(Kinda.ForwarderTest.DecodedKind, :primitive))(ref) do
        {:primitive, ref}
      end
    end
  end

  test "resource kinds can use the default forwarder make path" do
    assert %RawKind{ref: 7} = RawKind.make(7)
  end

  test "raw_call/3 leaves wrapping to the caller" do
    assert {:kind, DecodedKind, _ref} = Runtime.raw_call(DecodedKind, :wrap, [])
  end

  test "raw_call/3 prefers raw companion modules when available" do
    assert {:primitive, :ok} ==
             Runtime.raw_call(DecodedKind, :primitive, [%DecodedKind{ref: :ok}])
  end

  test "call_kind/4 prefers call/3 when available" do
    assert %DecodedKind{} = Kinda.Forwarder.call_kind(Runtime, DecodedKind, :wrap, [])
  end

  test "forward/3 wraps decoded kind tuples" do
    assert %DecodedKind{ref: ref} = Runtime.forward(DecodedKind, :wrap, [])
    assert is_reference(ref)
  end

  test "invoke_kind_nif/5 unwraps refs and normalizes kind results" do
    assert %DecodedKind{ref: ref} =
             Kinda.Forwarder.invoke_kind_nif(Runtime, FakeNIF, DecodedKind, :wrap, [])

    assert is_reference(ref)
  end

  test "invoke_public_nif/4 unwraps refs and normalizes the result" do
    ref = make_ref()

    assert {:primitive, ^ref} =
             Kinda.Forwarder.invoke_public_nif(
               Runtime,
               FakeNIF.Raw,
               Module.concat(DecodedKind, :primitive),
               [%DecodedKind{ref: ref}]
             )
  end

  test "check!/1 preserves metadata alongside wrapped kinds" do
    ref = make_ref()

    assert match?(
             {%DecodedKind{ref: ^ref}, :meta},
             Runtime.check!({{:kind, DecodedKind, ref}, :meta})
           )
  end

  test "to_term/1 routes resource-backed structs through primitive" do
    ref = make_ref()

    assert {:primitive, ref} == Runtime.to_term(%DecodedKind{ref: ref})
    assert 42 == Runtime.to_term(42)
  end

  test "check!/1 raises Kinda.CallError for string errors" do
    error =
      assert_raise Kinda.CallError, fn ->
        Runtime.check!({:error, "boom"})
      end

    assert Exception.message(error) =~ "boom"
  end

  test "check!/1 re-raises exception payloads" do
    assert_raise RuntimeError, "oops", fn ->
      Runtime.check!({:error, %RuntimeError{message: "oops"}})
    end
  end
end
