defmodule Kinda.QuickJSLifecycleTest do
  use ExUnit.Case, async: false

  alias Kinda.QuickJS.{Context, Runtime}

  test "isolates realms while sharing one runtime" do
    runtime = Kinda.QuickJS.open()
    first = Kinda.QuickJS.context(runtime)
    second = Kinda.QuickJS.context(runtime)

    assert Context.eval(first, "globalThis.answer = 42") == 42
    assert Context.eval(first, "answer") == 42
    assert Context.eval(second, "typeof answer") == "undefined"
  end

  test "enforces memory and execution budgets" do
    runtime = Kinda.QuickJS.open(memory_limit: 2_000_000, stack_limit: 256_000)
    context = Kinda.QuickJS.context(runtime)

    assert Runtime.stats(runtime).limit == 2_000_000

    assert_raise Kinda.CallError, ~r/FailedToEvaluate/, fn ->
      Context.eval(context, "while (true) {}", interrupt_budget: 10)
    end
  end

  test "a context retains its runtime and close is idempotent" do
    runtime = Kinda.QuickJS.open()
    context = Kinda.QuickJS.context(runtime)

    assert :ok = Runtime.close(runtime)
    assert :ok = Runtime.close(runtime)
    assert Context.eval(context, "6 * 7") == 42
    assert :ok = Context.close(context)
    assert :ok = Context.close(context)

    assert_raise Kinda.CallError, ~r/ClosedContext/, fn -> Context.eval(context, "1") end
  end

  test "independent runtimes execute concurrently" do
    contexts = for _ <- 1..4, do: Kinda.QuickJS.open() |> Kinda.QuickJS.context()
    tasks = for context <- contexts, do: Task.async(fn -> Context.eval(context, "21 * 2") end)
    assert Task.await_many(tasks) == [42, 42, 42, 42]
  end
end
