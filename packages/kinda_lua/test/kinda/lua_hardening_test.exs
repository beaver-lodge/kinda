defmodule Kinda.LuaHardeningTest do
  use ExUnit.Case, async: true
  alias Kinda.Lua
  alias Kinda.Lua.{Bytecode, Coroutine, Native, Userdata, VM}
  alias Kinda.Python.Execution
  alias Kinda.Testing.{Isolated, NativeScenario}

  test "runs version-bound bytecode in independent VMs" do
    bytecode = Lua.compile("return 40 + 2, 'beam'")
    assert Lua.run(Lua.open(), bytecode) == [42, "beam"]
    assert Lua.run(Lua.open(), bytecode) == [42, "beam"]
    assert :ok = Bytecode.close(bytecode)
    assert_raise Kinda.CallError, ~r/ClosedBytecode/, fn -> Lua.run(Lua.open(), bytecode) end
  end

  test "full userdata retains its VM and is visible to Lua" do
    vm = Lua.open()
    userdata = Lua.userdata(vm, 42)
    assert Userdata.value(userdata) == 42
    assert Lua.eval(vm, "return tostring(kinda_userdata):match('kinda.userdata') ~= nil") == true
    assert :ok = VM.close(vm)
    assert Userdata.value(userdata) == 42
    assert :ok = Userdata.close(userdata)
  end

  test "mixed children tolerate arbitrary close and GC order" do
    Enum.each(1..100, fn index ->
      vm = Lua.open()
      coroutine = Lua.coroutine(vm, "coroutine.yield(#{index})")
      userdata = Lua.userdata(vm, index)
      bytecode = Lua.compile("return #{index}")

      case rem(index, 4) do
        0 -> VM.close(vm)
        1 -> Coroutine.close(coroutine)
        2 -> Userdata.close(userdata)
        3 -> Bytecode.close(bytecode)
      end
    end)

    :erlang.garbage_collect(self())
    assert true
  end

  test "live resources survive a NIF hot upgrade" do
    if match?({:win32, _}, :os.type()) do
      assert Lua.eval("return 42") == 42
    else
      steps = [
        {:call, :vm, {Lua, :open, []}},
        {:call, :coroutine,
         {Lua, :coroutine, [{:resource, :vm}, "coroutine.yield(41); return 42"]}},
        {:call, :userdata, {Lua, :userdata, [{:resource, :vm}, 42]}},
        {:call, :bytecode, {Lua, :compile, ["return 42"]}},
        {:upgrade, Native, :kinda_lua, "KindaLuaNIF"},
        {:expect, {:yielded, [41]}, {Coroutine, :resume, [{:resource, :coroutine}]}},
        {:expect, 42, {Userdata, :value, [{:resource, :userdata}]}},
        {:expect, 42, {Lua, :run, [{:resource, :vm}, {:resource, :bytecode}]}},
        {:expect, :ok, {Coroutine, :close, [{:resource, :coroutine}]}},
        {:expect, :ok, {Userdata, :close, [{:resource, :userdata}]}},
        {:expect, :ok, {Bytecode, :close, [{:resource, :bytecode}]}},
        {:expect, :ok, {VM, :close, [{:resource, :vm}]}},
        {:purge, Native}
      ]

      assert Isolated.run({NativeScenario, :run, [steps]}, timeout: 120_000) == :ok
    end
  end

  test "coexists with mruby, SQLite, DuckDB, and CPython NIF runtimes" do
    lua = Task.async(fn -> Lua.eval("return 6 * 7") end)
    mruby = Task.async(fn -> Kinda.MRuby.eval("6 * 7") end)
    sqlite = Task.async(fn -> Kinda.SQLite.sqlite_version() end)
    duckdb = Task.async(fn -> Kinda.DuckDB.query_int64("select 42") end)
    python = Kinda.Python.eval_async("40 + 2")

    assert Task.await(lua, 30_000) == 42
    assert Task.await(mruby, 30_000) == 42
    assert is_binary(Task.await(sqlite, 30_000))
    assert Task.await(duckdb, 30_000) == 42
    assert Execution.await(python, 30_000) == 42
  end
end
