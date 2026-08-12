defmodule Kinda.MRubyHardeningTest do
  use ExUnit.Case, async: false
  alias Kinda.MRuby.{Native, Value, VM}
  alias Kinda.Python.Execution

  test "accounts allocations per VM and injects allocation failure" do
    left = VM.open()
    right = VM.open()
    left_value = VM.eval(left, "'x' * 10_000")
    left_stats = VM.allocator_stats(left)
    right_stats = VM.allocator_stats(right)
    assert left_stats.live_bytes > right_stats.live_bytes
    assert left_stats.peak_bytes >= left_stats.live_bytes
    Value.close(left_value)
    VM.close(left)
    VM.close(right)

    limited = VM.open(allocation_budget: 0)
    assert_raise Kinda.CallError, fn -> VM.eval(limited, "10_000.times { Object.new }") end
    VM.close(limited)
  end

  test "isolates classes installed by the default mrbgem profile" do
    assert Kinda.MRuby.build_profile() == "mruby-4.0.0/default-gembox/pic-v5-custom-allocf"
    left = VM.open()
    right = VM.open()

    marker =
      VM.eval(left, "Random.class_eval { def kinda_marker; 42; end }; Random.new.kinda_marker")

    isolated = VM.eval(right, "Random.new.respond_to?(:kinda_marker)")
    assert Value.to_term(marker) == 42
    assert Value.to_term(isolated) == false
    Value.close(marker)
    Value.close(isolated)
    VM.close(left)
    VM.close(right)
  end

  @tag :tmp_dir
  test "live VM and bytecode resources survive a NIF hot upgrade", %{tmp_dir: tmp_dir} do
    if match?({:win32, _}, :os.type()) do
      assert Kinda.MRuby.eval("40 + 2") == 42
    else
      vm = VM.open()
      bytecode = Kinda.MRuby.compile("40 + 2")
      upgrade = copy_nif!(tmp_dir)
      original = remember_module(Native)
      on_exit(fn -> restore_module(original) end)

      assert {:module, Native, _binary, _result} = hot_upgrade_module(Native, upgrade)
      value = Kinda.MRuby.run(vm, bytecode)
      assert Value.to_term(value) == 42
      Value.close(value)
      VM.close(vm)
      :erlang.garbage_collect()
      :code.purge(Native)
    end
  end

  test "coexists with SQLite, DuckDB, and CPython NIF runtimes" do
    mruby = Task.async(fn -> Kinda.MRuby.eval("6 * 7") end)
    sqlite = Task.async(fn -> Kinda.SQLite.sqlite_version() end)
    duckdb = Task.async(fn -> Kinda.DuckDB.query_int64("select 42") end)
    python = Kinda.Python.eval_async("40 + 2")

    assert Task.await(mruby, 30_000) == 42
    assert is_binary(Task.await(sqlite, 30_000))
    assert Task.await(duckdb, 30_000) == 42
    assert Execution.await(python, 30_000) == 42
  end

  defp copy_nif!(tmp_dir) do
    base = "#{:code.priv_dir(:kinda_mruby)}/lib/libKindaMRubyNIF"

    source =
      Enum.find_value([".so", ".dylib", ".dll"], fn extension ->
        path = base <> extension
        if File.exists?(path), do: path
      end) || raise "could not find mruby NIF"

    destination = Path.join(tmp_dir, "libKindaMRubyNIFUpgrade")
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

        def load_nif do
          :erlang.load_nif(unquote(String.to_charlist(nif_file)), 0)
        end

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
