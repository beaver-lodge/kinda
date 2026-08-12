defmodule Kinda.LuaHardeningTest do
  use ExUnit.Case, async: false
  alias Kinda.Lua
  alias Kinda.Lua.{Bytecode, Coroutine, Native, Userdata, VM}
  alias Kinda.Python.Execution

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

  @tag :tmp_dir
  test "live resources survive a NIF hot upgrade", %{tmp_dir: tmp_dir} do
    if match?({:win32, _}, :os.type()) do
      assert Lua.eval("return 42") == 42
    else
      vm = Lua.open()
      coroutine = Lua.coroutine(vm, "coroutine.yield(41); return 42")
      userdata = Lua.userdata(vm, 42)
      bytecode = Lua.compile("return 42")
      upgrade = copy_nif!(tmp_dir)
      original = remember_module(Native)
      on_exit(fn -> restore_module(original) end)

      assert {:module, Native, _binary, _result} = hot_upgrade_module(Native, upgrade)
      assert Coroutine.resume(coroutine) == {:yielded, [41]}
      assert Userdata.value(userdata) == 42
      assert Lua.run(vm, bytecode) == 42
      Coroutine.close(coroutine)
      Userdata.close(userdata)
      Bytecode.close(bytecode)
      VM.close(vm)
      :code.purge(Native)
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

  defp copy_nif!(tmp_dir) do
    base = "#{:code.priv_dir(:kinda_lua)}/lib/libKindaLuaNIF"

    source =
      Enum.find_value([".so", ".dylib", ".dll"], fn extension ->
        path = base <> extension
        if File.exists?(path), do: path
      end) || raise "could not find Lua NIF"

    destination = Path.join(tmp_dir, "libKindaLuaNIFUpgrade")
    File.cp!(source, destination <> Path.extname(source))
    destination
  end

  defp remember_module(module) do
    {module, binary, path} = :code.get_object_code(module)
    {module, binary, path}
  end

  defp restore_module({module, binary, path}) do
    assert {:module, ^module} = :code.load_binary(module, path, binary)
    :code.purge(module)
  end

  defp hot_upgrade_module(module, nif_file) do
    stubs =
      for {name, arity} <- module.__info__(:functions), name != :load_nif do
        args = Macro.generate_arguments(arity, __MODULE__)

        quote do
          def unquote(name)(unquote_splicing(args)),
            do: :erlang.nif_error({:nif_not_loaded, unquote(name)})
        end
      end

    body =
      quote do
        @on_load :load_nif
        def load_nif, do: :erlang.load_nif(unquote(String.to_charlist(nif_file)), 0)
        unquote_splicing(stubs)
      end

    compiler_options = Code.compiler_options()
    Code.compiler_options(ignore_module_conflict: true)

    try do
      Module.create(module, body, Macro.Env.location(__ENV__))
    after
      Code.compiler_options(compiler_options)
    end
  end
end
