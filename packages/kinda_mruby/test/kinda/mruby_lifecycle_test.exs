defmodule Kinda.MRubyLifecycleTest do
  use ExUnit.Case, async: false
  alias Kinda.MRuby.{Value, VM}

  test "isolates globals between VMs" do
    left = VM.open()
    right = VM.open()
    left_value = VM.eval(left, "$answer = 42")
    right_value = VM.eval(right, "$answer || -1")
    assert Value.to_term(left_value) == 42
    assert Value.to_term(right_value) == -1
    Value.close(left_value)
    Value.close(right_value)
    VM.close(left)
    VM.close(right)
  end

  test "a rooted child keeps a closing VM alive" do
    vm = VM.open()
    value = VM.eval(vm, "'kept alive'")
    assert :ok = VM.close(vm)
    assert Value.to_term(value) == "kept alive"
    assert :ok = Value.close(value)
    assert :ok = Value.close(value)
    assert :ok = VM.close(vm)
  end

  test "survives arbitrary VM and value GC order" do
    Enum.each(1..100, fn index ->
      vm = VM.open()
      value = VM.eval(vm, "'value-#{index}'")

      if rem(index, 2) == 0 do
        VM.close(vm)
        assert Value.to_term(value) == "value-#{index}"
        Value.close(value)
      else
        Value.close(value)
        VM.close(vm)
      end
    end)

    :erlang.garbage_collect()
  end

  test "contains exceptions without unwinding through the NIF" do
    vm = VM.open()

    assert_raise Kinda.CallError, ~r/FailedToEvaluate/, fn ->
      VM.eval(vm, "raise 'boom'")
    end

    value = VM.eval(vm, "6 * 7")
    assert Value.to_term(value) == 42
    Value.close(value)
    VM.close(vm)
  end
end
