defmodule Kinda.LuaLifecycleTest do
  use ExUnit.Case, async: true
  alias Kinda.Lua
  alias Kinda.Lua.VM

  test "keeps globals isolated between persistent VMs" do
    first = Lua.open()
    second = Lua.open()
    assert Lua.eval(first, "counter = 41; return counter + 1") == 42
    assert Lua.eval(first, "return counter") == 41
    assert Lua.eval(second, "return counter") == nil
  end

  test "returns multiple values in order" do
    vm = Lua.open()
    assert Lua.eval(vm, "return 1, 'two', true") == [1, "two", true]
  end

  test "tracks allocations and enforces a memory budget" do
    vm = Lua.open()
    assert Lua.eval(vm, "return 42") == 42
    assert %{calls: calls, live_bytes: live, peak_bytes: peak} = VM.allocator_stats(vm)
    assert calls > 0 and live > 0 and peak >= live

    limited = Lua.open(memory_limit: 32_000)

    assert_raise Kinda.CallError, fn ->
      Lua.eval(limited, "return string.rep('x', 100000)")
    end
  end

  test "close is idempotent and rejects later evaluation" do
    vm = Lua.open()
    assert :ok = VM.close(vm)
    assert :ok = VM.close(vm)
    assert_raise Kinda.CallError, ~r/ClosedVM/, fn -> Lua.eval(vm, "return 1") end
  end
end
