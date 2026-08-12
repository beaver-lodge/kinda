defmodule Kinda.QuickJSHardeningTest do
  use ExUnit.Case, async: false

  alias Kinda.QuickJS.{Bytecode, Context, Runtime}

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
    upgrade = copy_nif!(tmp_dir)
    original = remember_module(Kinda.QuickJS.Native)
    on_exit(fn -> restore_module(original) end)

    assert {:module, Kinda.QuickJS.Native, _binary, _result} =
             hot_upgrade_module(Kinda.QuickJS.Native, upgrade)

    assert Kinda.QuickJS.Value.to_term(value) == "still-live"
    assert :ok = Kinda.QuickJS.Value.close(value)
    assert :ok = Context.close(context)
    assert :ok = Runtime.close(runtime)
    :code.purge(Kinda.QuickJS.Native)
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

  defp copy_nif!(tmp_dir) do
    base = "#{:code.priv_dir(:kinda_quickjs)}/lib/libKindaQuickJSNIF"

    source =
      Enum.find_value([".so", ".dylib", ".dll"], fn extension ->
        path = base <> extension
        if File.exists?(path), do: path
      end) || raise "could not find QuickJS NIF"

    destination = Path.join(tmp_dir, "libKindaQuickJSNIFUpgrade")
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
