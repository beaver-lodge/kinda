defmodule Kinda.Testing.Lifecycle do
  @moduledoc """
  Deterministic lifecycle scenarios for owned native resources.

  The caller supplies release and probe callbacks, so production resources do
  not need test hooks. Every scenario uses a stable seed and reports the exact
  release order on failure.
  """

  alias Kinda.Resource.Declaration

  @type resources :: %{required(atom() | binary()) => term()}

  @spec permutations([Declaration.t()], keyword()) :: [[Declaration.t()]]
  def permutations(declarations, options \\ []) when is_list(declarations) do
    count = Keyword.get(options, :count, :all)
    seed = Keyword.get(options, :seed, 0)
    base = Enum.sort_by(declarations, & &1.identity)

    case count do
      :all ->
        all_permutations(base)

      count when is_integer(count) and count > 0 ->
        [base, Enum.reverse(base) | seeded_permutations(base, seed, count)]
        |> Enum.uniq()

      invalid ->
        raise ArgumentError,
              "permutation count must be :all or a positive integer, got: #{inspect(invalid)}"
    end
  end

  @doc """
  Verifies every requested release order using freshly-created resources.

  `:setup` returns a map keyed by declaration identity. `:release` receives
  the declaration and its corresponding resource. `:probe` runs after every
  release with the resources that have not been explicitly released yet.
  """
  @spec verify!([Declaration.t()], keyword()) :: :ok
  def verify!(declarations, options) do
    setup = Keyword.fetch!(options, :setup)
    release = Keyword.fetch!(options, :release)
    probe = Keyword.get(options, :probe, fn _remaining -> :ok end)

    owner_graph!(declarations)

    Enum.each(permutations(declarations, options), fn order ->
      run_order!(declarations, order, setup, release, probe)
    end)

    :ok
  end

  @spec owner_graph!([Declaration.t()]) :: %{
          optional(atom() | binary()) => atom() | binary() | nil
        }
  def owner_graph!(declarations) do
    graph = Map.new(declarations, &{&1.identity, &1.owner})

    Enum.each(graph, fn {identity, owner} ->
      if owner != nil and not Map.has_key?(graph, owner) do
        raise ArgumentError, "resource #{inspect(identity)} has unknown owner #{inspect(owner)}"
      end
    end)

    graph
  end

  defp run_order!(declarations, order, setup, release, probe) do
    resources = setup.()

    Enum.each(declarations, fn declaration ->
      Map.fetch!(resources, declaration.identity)
    end)

    _remaining =
      Enum.reduce(order, resources, fn declaration, remaining ->
        :ok = release.(declaration, Map.fetch!(resources, declaration.identity))
        next = Map.delete(remaining, declaration.identity)
        :ok = probe.(next)
        next
      end)

    :ok
  end

  defp seeded_permutations(resources, seed, count) do
    Enum.map(1..count, fn offset ->
      :rand.seed(:exsss, {seed + offset + 1, seed + offset + 2, seed + offset + 3})
      Enum.shuffle(resources)
    end)
  end

  defp all_permutations([]), do: [[]]

  defp all_permutations(resources) do
    for resource <- resources,
        rest <- all_permutations(List.delete(resources, resource)) do
      [resource | rest]
    end
  end
end
