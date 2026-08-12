defmodule Kinda.PythonConcurrencyTest do
  use ExUnit.Case, async: true
  alias Kinda.Python.Execution

  test "runs independent OWN_GIL interpreters on concurrent dirty scheduler threads" do
    executions =
      Enum.map(1..8, fn _index ->
        Kinda.Python.eval_async("sum(i * i for i in range(250_000))")
      end)

    assert Enum.map(executions, &Execution.await(&1, 30_000)) ==
             List.duplicate(5_208_302_083_375_000, 8)
  end

  test "leaves no thread state behind after execution" do
    assert Kinda.Python.eval_async("40 + 2") |> Execution.await() == 42
    assert Kinda.Python.eval_async("6 * 7") |> Execution.await() == 42
  end
end
