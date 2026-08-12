defmodule Kinda.LuaTest do
  use ExUnit.Case, async: true

  test "reports the pinned Lua runtime version" do
    assert Kinda.Lua.version() == "Lua 5.4.8"
  end

  test "evaluates primitive Lua values" do
    assert Kinda.Lua.eval("return nil") == nil
    assert Kinda.Lua.eval("return true") == true
    assert Kinda.Lua.eval("return 40 + 2") == 42
    assert_in_delta Kinda.Lua.eval("return 7 / 2"), 3.5, 0.000_001
    assert Kinda.Lua.eval("return 'beam'") == "beam"
  end

  test "turns Lua errors into NIF errors" do
    assert_raise Kinda.CallError, ~r/FailedToEvaluate/, fn ->
      Kinda.Lua.eval("error('boom')")
    end
  end
end
