defmodule Kinda.Testing.IsolatedTest do
  use ExUnit.Case, async: true

  alias Kinda.Testing.{Isolated, IsolatedScenario}

  test "runs an MFA in an isolated BEAM" do
    assert Isolated.run({IsolatedScenario, :add, [20, 22]}) == 42
  end

  test "returns formatted child exceptions" do
    assert_raise RuntimeError, ~r/isolated BEAM failed.*boom/s, fn ->
      Isolated.run({IsolatedScenario, :fail, []})
    end
  end
end
