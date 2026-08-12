defmodule Kinda.MRubyConcurrencyTest do
  use ExUnit.Case, async: false
  alias Kinda.MRuby.{Bytecode, Value, VM}

  test "runs independent VMs on concurrent dirty CPU schedulers" do
    tasks =
      Enum.map(1..8, fn index ->
        Task.async(fn ->
          vm = VM.open()
          value = VM.eval(vm, "(1..200_000).reduce(#{index}) { |sum, n| sum + n }")
          result = Value.to_term(value)
          Value.close(value)
          VM.close(vm)
          result
        end)
      end)

    assert Enum.map(tasks, &Task.await(&1, 30_000)) ==
             Enum.map(1..8, &(20_000_100_000 + &1))
  end

  test "reuses bytecode across isolated VMs" do
    bytecode = Bytecode.compile("$counter = ($counter || 0) + 1")

    results =
      Enum.map(1..4, fn _index ->
        vm = VM.open()
        first = VM.run(vm, bytecode)
        second = VM.run(vm, bytecode)
        pair = {Value.to_term(first), Value.to_term(second)}
        Value.close(first)
        Value.close(second)
        VM.close(vm)
        pair
      end)

    assert results == List.duplicate({1, 2}, 4)
    assert :ok = Bytecode.close(bytecode)
    assert :ok = Bytecode.close(bytecode)
  end

  test "rejects malformed source during compilation" do
    assert_raise Kinda.CallError, ~r/FailedToCompile/, fn ->
      Bytecode.compile("def missing_end")
    end
  end
end
