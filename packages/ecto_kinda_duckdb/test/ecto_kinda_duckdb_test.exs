defmodule EctoKindaDuckDBTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.KindaDuckDB.Connection
  alias EctoKindaDuckDB.{Metric, TestRepo}

  setup do
    TestRepo.query!("drop table if exists metrics")
    TestRepo.query!("create table metrics(category varchar, value bigint)")
    TestRepo.query!("insert into metrics values ('a', 1), ('a', 2), ('b', 3)")
    :ok
  end

  test "runs parameterized SQL through Kinda DuckDB" do
    assert %{columns: ["answer"], rows: [[42]]} =
             TestRepo.query!("select $1::bigint + $2::bigint as answer", [40, 2])
  end

  test "runs Ecto analytical SELECT queries" do
    query =
      from metric in Metric,
        where: metric.category == ^"a",
        group_by: metric.category,
        select: {metric.category, type(fragment("sum(?)::bigint", metric.value), :integer)}

    assert TestRepo.all(query) == [{"a", 3}]
  end

  test "streams bounded query results inside a transaction" do
    query = from metric in Metric, order_by: metric.value, select: metric.value

    assert {:ok, [1, 2, 3]} =
             TestRepo.transaction(fn ->
               query |> TestRepo.stream(max_rows: 2) |> Enum.to_list()
             end)
  end

  test "commits and rolls back top-level transactions" do
    assert {:ok, :committed} =
             TestRepo.transaction(fn ->
               TestRepo.query!("insert into metrics values ('commit', 4)")
               :committed
             end)

    assert {:error, :rolled_back} =
             TestRepo.transaction(fn ->
               TestRepo.query!("insert into metrics values ('rollback', 5)")
               TestRepo.rollback(:rolled_back)
             end)

    assert %{rows: [[1]]} =
             TestRepo.query!("select count(*) from metrics where category = 'commit'")

    assert %{rows: [[0]]} =
             TestRepo.query!("select count(*) from metrics where category = 'rollback'")
  end

  test "fails unsupported schema writes explicitly" do
    assert_raise Kinda.DuckDB.Error, ~r/insert is not supported/, fn ->
      TestRepo.insert!(%Metric{category: "unsupported", value: 1})
    end
  end

  test "fails migration SQL generation explicitly" do
    assert_raise Kinda.DuckDB.Error, ~r/migration is not supported/, fn ->
      Connection.execute_ddl({:create, nil})
    end
  end
end
