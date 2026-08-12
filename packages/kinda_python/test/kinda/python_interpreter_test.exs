defmodule Kinda.PythonInterpreterTest do
  use ExUnit.Case, async: false
  alias Kinda.Python.{Interpreter, Value}

  test "isolates globals across interpreters" do
    left = Interpreter.open()
    right = Interpreter.open()

    left_value = Interpreter.eval(left, "globals().__setitem__('answer', 41) or answer + 1")
    right_value = Interpreter.eval(right, "globals().get('answer', -1)")
    assert Value.to_term(left_value) == 42
    assert Value.to_term(right_value) == -1
    assert :ok = Value.close(left_value)
    assert :ok = Value.close(right_value)
    assert :ok = Interpreter.close(left)
    assert :ok = Interpreter.close(right)
  end

  test "a value keeps its closing parent alive until arbitrary-order GC" do
    interpreter = Interpreter.open()
    value = Interpreter.eval(interpreter, "'kept alive'")
    assert :ok = Interpreter.close(interpreter)
    assert Value.to_term(value) == "kept alive"
    assert :ok = Value.close(value)
    assert :ok = Value.close(value)
  end

  test "close is idempotent" do
    interpreter = Interpreter.open()
    assert :ok = Interpreter.close(interpreter)
    assert :ok = Interpreter.close(interpreter)
  end
end
