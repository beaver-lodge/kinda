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
    def unquote(Module.concat(Kinda.ForwarderTest.RawKind, "make"))(value), do: value

    def unquote(Module.concat(Kinda.ForwarderTest.DecodedKind, :wrap))() do
      {:kind, Kinda.ForwarderTest.DecodedKind, make_ref()}
    end

    def unquote(Module.concat(Kinda.ForwarderTest.DecodedKind, :primitive))(ref) do
      {:primitive, ref}
    end
  end

  test "resource kinds can use the default forwarder make path" do
    assert %RawKind{ref: 7} = RawKind.make(7)
  end

  test "forward/3 wraps decoded kind tuples" do
    assert %DecodedKind{ref: ref} = Runtime.forward(DecodedKind, :wrap, [])
    assert is_reference(ref)
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
