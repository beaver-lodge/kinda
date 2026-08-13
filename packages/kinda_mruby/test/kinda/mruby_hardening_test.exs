defmodule Kinda.MRubyHardeningTest do
  use ExUnit.Case, async: true
  alias Kinda.MRuby.{Native, Value, VM}
  alias Kinda.Python.Execution
  alias Kinda.Testing.{Isolated, NativeScenario}

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

  test "live VM and bytecode resources survive a NIF hot upgrade" do
    if match?({:win32, _}, :os.type()) do
      assert Kinda.MRuby.eval("40 + 2") == 42
    else
      steps = [
        {:call, :vm, {VM, :open, []}},
        {:call, :bytecode, {Kinda.MRuby, :compile, ["40 + 2"]}},
        {:upgrade, Native, :kinda_mruby, "KindaMRubyNIF"},
        {:call, :value, {Kinda.MRuby, :run, [{:resource, :vm}, {:resource, :bytecode}]}},
        {:expect, 42, {Value, :to_term, [{:resource, :value}]}},
        {:expect, :ok, {Value, :close, [{:resource, :value}]}},
        {:expect, :ok, {VM, :close, [{:resource, :vm}]}},
        :garbage_collect,
        {:purge, Native}
      ]

      assert Isolated.run({NativeScenario, :run, [steps]}, timeout: 120_000) == :ok
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
end
