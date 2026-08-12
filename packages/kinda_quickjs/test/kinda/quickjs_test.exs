defmodule Kinda.QuickJSTest do
  use ExUnit.Case, async: true

  test "reports the pinned QuickJS runtime version" do
    assert Kinda.QuickJS.version() == "2026-06-04"
  end

  test "evaluates primitive JavaScript values" do
    assert Kinda.QuickJS.eval("undefined") == :undefined
    assert Kinda.QuickJS.eval("null") == nil
    assert Kinda.QuickJS.eval("true") == true
    assert Kinda.QuickJS.eval("40 + 2") == 42
    assert_in_delta Kinda.QuickJS.eval("7 / 2"), 3.5, 0.000_001
    assert Kinda.QuickJS.eval("'beam'") == "beam"
  end

  test "turns QuickJS errors into NIF errors" do
    assert_raise Kinda.CallError, ~r/FailedToEvaluate/, fn ->
      Kinda.QuickJS.eval("throw new Error('boom')")
    end
  end
end
