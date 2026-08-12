defmodule Kinda.QuickJSPromiseTest do
  use ExUnit.Case, async: false

  alias Kinda.QuickJS.{Context, Runtime, Value}

  test "keeps primitive and object values rooted in their context" do
    runtime = Kinda.QuickJS.open()
    context = Kinda.QuickJS.context(runtime)
    value = Context.value(context, "'beam'")

    assert Value.to_term(value) == "beam"
    assert :ok = Context.close(context)
    assert :ok = Runtime.close(runtime)
    assert Value.to_term(value) == "beam"
    assert :ok = Value.close(value)
  end

  test "drives promises through the explicit runtime job queue" do
    runtime = Kinda.QuickJS.open()
    context = Kinda.QuickJS.context(runtime)
    promise = Context.value(context, "Promise.resolve(40).then(value => value + 2)")

    assert Value.promise_state(promise) == :pending
    assert Runtime.run_jobs(runtime) == 1
    assert Value.promise_state(promise) == :fulfilled
    assert Value.promise_result(promise) == 42
  end

  test "limits job execution" do
    runtime = Kinda.QuickJS.open()
    context = Kinda.QuickJS.context(runtime)
    promise = Context.value(context, "Promise.resolve(1).then(x => x + 1).then(x => x + 1)")

    assert Runtime.run_jobs(runtime, 1) == 1
    assert Value.promise_state(promise) == :pending
    assert Runtime.run_jobs(runtime, 1) == 1
    assert Value.promise_state(promise) == :fulfilled
  end

  test "parent, context, and value tolerate arbitrary GC order" do
    parent = self()

    spawn(fn ->
      runtime = Kinda.QuickJS.open()
      context = Kinda.QuickJS.context(runtime)
      value = Context.value(context, "Promise.resolve(42)")
      send(parent, {:resources, runtime, context, value})
    end)

    assert_receive {:resources, runtime, context, value}
    :erlang.garbage_collect()
    assert Value.promise_state(value) == :fulfilled
    assert :ok = Runtime.close(runtime)
    assert :ok = Context.close(context)
    assert Value.promise_result(value) == 42
  end
end
