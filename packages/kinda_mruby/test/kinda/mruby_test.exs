defmodule Kinda.MRubyTest do
  use ExUnit.Case, async: true

  test "reports the pinned mruby runtime version" do
    assert Kinda.MRuby.version() == "4.0.0"
  end

  test "evaluates an integer expression" do
    assert Kinda.MRuby.eval("40 + 2") == 42
  end

  test "evaluates a string expression" do
    assert Kinda.MRuby.eval("'beam'") == "beam"
  end

  test "turns Ruby exceptions into NIF errors" do
    assert_raise Kinda.CallError, ~r/FailedToEvaluate/, fn ->
      Kinda.MRuby.eval("raise 'boom'")
    end
  end
end
