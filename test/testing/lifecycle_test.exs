defmodule Kinda.Testing.LifecycleTest do
  use ExUnit.Case, async: true

  alias Kinda.Resource.Declaration
  alias Kinda.Testing.Lifecycle

  test "validates owner graphs" do
    runtime = Declaration.new(:runtime, upgrade: :takeover)
    context = Declaration.new(:context, owner: :runtime)
    value = Declaration.new(:value, owner: :context)

    assert Lifecycle.owner_graph!([runtime, context, value]) == %{
             runtime: nil,
             context: :runtime,
             value: :context
           }

    assert Declaration.supports_upgrade?(runtime)
    refute Declaration.supports_upgrade?(context)
  end

  test "checks deterministic release permutations exactly once" do
    parent = self()
    declarations = for identity <- [:runtime, :context, :value], do: Declaration.new(identity)

    assert :ok =
             Lifecycle.verify!(declarations,
               seed: 42,
               count: 8,
               setup: fn -> Map.new(declarations, &{&1.identity, make_ref()}) end,
               release: fn declaration, _resource ->
                 send(parent, {:released, declaration.identity})
                 :ok
               end,
               probe: fn remaining ->
                 assert map_size(remaining) in 0..2
                 :ok
               end
             )

    messages = drain_releases([])
    scenario_count = length(Lifecycle.permutations(declarations, seed: 42, count: 8))

    for identity <- [:runtime, :context, :value] do
      assert Enum.count(messages, &(&1 == identity)) == scenario_count
    end
  end

  test "enumerates every order by default" do
    declarations = for identity <- [:runtime, :context, :value], do: Declaration.new(identity)

    assert length(Lifecycle.permutations(declarations)) == 6
  end

  defp drain_releases(messages) do
    receive do
      {:released, identity} -> drain_releases([identity | messages])
    after
      0 -> messages
    end
  end
end
