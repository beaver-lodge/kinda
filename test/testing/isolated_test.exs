defmodule Kinda.Testing.IsolatedTest do
  use ExUnit.Case, async: true

  alias Kinda.Testing.{Isolated, IsolatedScenario}

  test "runs an MFA in an isolated BEAM" do
    assert Isolated.run({IsolatedScenario, :add, [20, 22]}) == 42
  end

  test "round-trips Unicode and arbitrary binary bytes" do
    value = {"隔离进程", <<0, 131, 255>>}

    assert Isolated.run({IsolatedScenario, :identity, [value]}) == value
  end

  test "returns formatted child exceptions" do
    assert_raise RuntimeError, ~r/isolated BEAM failed.*boom/s, fn ->
      Isolated.run({IsolatedScenario, :fail, []})
    end
  end

  test "ignores child stdout outside the control reply" do
    assert Isolated.run({IsolatedScenario, :noisy, [42]}) == 42
  end
end
