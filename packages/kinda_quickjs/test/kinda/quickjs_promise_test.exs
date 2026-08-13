defmodule Kinda.QuickJSPromiseTest do
  use ExUnit.Case, async: true

  alias Kinda.QuickJS.{Context, Runtime, Value}
  alias Kinda.Resource.Declaration
  alias Kinda.Testing.Lifecycle

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
    declarations = [
      Declaration.new(:runtime),
      Declaration.new(:context, owner: :runtime),
      Declaration.new(:value, owner: :context)
    ]

    assert :ok =
             Lifecycle.verify!(declarations,
               setup: fn ->
                 runtime = Kinda.QuickJS.open()
                 context = Kinda.QuickJS.context(runtime)
                 value = Context.value(context, "Promise.resolve(42)")
                 %{runtime: runtime, context: context, value: value}
               end,
               release: &close_resource/2,
               probe: fn remaining ->
                 if value = remaining[:value], do: assert(Value.promise_result(value) == 42)
                 :erlang.garbage_collect()
                 :ok
               end
             )
  end

  defp close_resource(%Declaration{identity: :runtime}, runtime), do: Runtime.close(runtime)
  defp close_resource(%Declaration{identity: :context}, context), do: Context.close(context)
  defp close_resource(%Declaration{identity: :value}, value), do: Value.close(value)
end
