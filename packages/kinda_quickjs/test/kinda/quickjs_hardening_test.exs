defmodule Kinda.QuickJSHardeningTest do
  use ExUnit.Case, async: false

  alias Kinda.QuickJS.{Bytecode, Context, Runtime}
  alias Kinda.Testing.NIFUpgrade

  test "loads only explicitly registered in-memory ES modules" do
    runtime = Kinda.QuickJS.open()
    context = Kinda.QuickJS.context(runtime)
    assert :ok = Runtime.register_module(runtime, "math", "export const answer = 42")

    assert :ok =
             Context.eval_module(
               context,
               "import { answer } from 'math'; globalThis.result = answer"
             )

    assert Context.eval(context, "result") == 42

    assert_raise Kinda.CallError, ~r/FailedToEvaluate/, fn ->
      Context.eval_module(context, "import 'not-registered'")
    end
  end

  test "runs version-bound bytecode in another context" do
    runtime = Kinda.QuickJS.open()
    compiler = Kinda.QuickJS.context(runtime)
    target = Kinda.QuickJS.context(runtime)
    bytecode = Context.compile(compiler, "40 + 2")

    assert Context.run(target, bytecode) == 42
    assert :ok = Bytecode.close(bytecode)
  end

  @tag :tmp_dir
  test "live resources survive a NIF hot upgrade", %{tmp_dir: tmp_dir} do
    runtime = Kinda.QuickJS.open()
    context = Kinda.QuickJS.context(runtime)
    value = Context.value(context, "'still-live'")
    NIFUpgrade.run!(
      Kinda.QuickJS.Native,
      :kinda_quickjs,
      "KindaQuickJSNIF",
      tmp_dir,
      fn ->
        assert Kinda.QuickJS.Value.to_term(value) == "still-live"
        assert :ok = Kinda.QuickJS.Value.close(value)
        assert :ok = Context.close(context)
        assert :ok = Runtime.close(runtime)
      end
    )
  end

  test "coexists with Lua, mruby, CPython, SQLite, and DuckDB" do
    assert Kinda.QuickJS.eval("6 * 7") == 42
    assert Kinda.Lua.eval("return 6 * 7") == 42
    assert Kinda.MRuby.eval("6 * 7") == 42

    python = Kinda.Python.open()
    python_value = Kinda.Python.eval(python, "6 * 7")
    assert Kinda.Python.Value.to_term(python_value) == 42
    assert :ok = Kinda.Python.Value.close(python_value)

    {:ok, sqlite} = Kinda.SQLite.open(":memory:")
    assert {:ok, result} = Kinda.SQLite.query(sqlite, "SELECT 42 AS value")
    assert result.rows == [[42]]

    duckdb = Kinda.DuckDB.open(":memory:")
    connection = Kinda.DuckDB.connect(duckdb)

    assert Kinda.DuckDB.query(connection, "SELECT 42 AS value").columns == [
             %{name: "value", values: [42]}
           ]
  end

end
