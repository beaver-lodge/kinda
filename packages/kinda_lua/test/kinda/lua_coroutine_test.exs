defmodule Kinda.LuaCoroutineTest do
  use ExUnit.Case, async: true
  alias Kinda.Lua
  alias Kinda.Lua.{Coroutine, VM}

  test "resumes a coroutine through yields to completion" do
    coroutine = Lua.coroutine(Lua.open(), "coroutine.yield(1); coroutine.yield('two'); return 3")
    assert Coroutine.resume(coroutine) == {:yielded, [1]}
    assert Coroutine.resume(coroutine) == {:yielded, ["two"]}
    assert Coroutine.resume(coroutine) == {:done, [3]}
  end

  test "a coroutine keeps its parent state alive after VM close" do
    vm = Lua.open()
    coroutine = Lua.coroutine(vm, "coroutine.yield(42); return 43")
    assert :ok = VM.close(vm)
    assert Coroutine.resume(coroutine) == {:yielded, [42]}
    assert Coroutine.resume(coroutine) == {:done, [43]}
    assert :ok = Coroutine.close(coroutine)
  end

  test "parent and child tolerate arbitrary garbage collection order" do
    Enum.each(1..50, fn _ ->
      vm = Lua.open()
      coroutine = Lua.coroutine(vm, "coroutine.yield(1)")
      if :rand.uniform(2) == 1, do: VM.close(vm), else: Coroutine.close(coroutine)
    end)

    :erlang.garbage_collect(self())
    assert true
  end

  test "independent VMs can execute concurrently" do
    tasks =
      for value <- 1..24 do
        Task.async(fn -> Lua.eval(Lua.open(), "return #{value} * 2") end)
      end

    assert Task.await_many(tasks) == Enum.map(1..24, &(&1 * 2))
  end
end
