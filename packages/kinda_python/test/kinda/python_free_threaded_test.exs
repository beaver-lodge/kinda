defmodule Kinda.PythonFreeThreadedTest do
  use ExUnit.Case, async: true

  alias Kinda.Python.Execution

  @tag :free_threaded
  test "the free-threaded profile runs concurrent isolated work without enabling shared objects" do
    if Kinda.Python.free_threaded_build?() do
      executions = Enum.map(1..4, fn _index -> Kinda.Python.eval_async("sum(range(500_000))") end)

      assert Enum.map(executions, &Execution.await(&1, 30_000)) ==
               List.duplicate(124_999_750_000, 4)
    end
  end
end
