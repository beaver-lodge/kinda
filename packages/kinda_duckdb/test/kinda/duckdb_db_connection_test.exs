defmodule Kinda.DuckDBDBConnectionTest do
  use ExUnit.Case, async: true

  alias Kinda.DuckDB.DBConnection, as: Driver
  alias Kinda.DuckDB.{DBResult, Query}

  setup do
    start_supervised!({Driver, database: ":memory:"})
    |> then(&%{pool: &1})
  end

  test "executes parameterized row-oriented queries", %{pool: pool} do
    assert %DBResult{columns: ["total"], rows: [[42]], num_rows: 1} =
             Driver.query!(pool, "select ?::bigint + ?::bigint as total", [40, 2])
  end

  test "streams bounded batches without repeating rows", %{pool: pool} do
    results =
      DBConnection.run(pool, fn connection ->
        connection
        |> Driver.stream("select * from range(5) values_table(value)", [], max_rows: 2)
        |> Enum.to_list()
      end)

    assert Enum.map(results, & &1.rows) == [[[0], [1]], [[2], [3]], [[4]]]
  end

  test "commits and rolls back transactions", %{pool: pool} do
    Driver.query!(pool, "create table events(id bigint)")

    assert {:ok, _result} =
             DBConnection.transaction(pool, fn connection ->
               Driver.query!(connection, "insert into events values (1)")
             end)

    assert {:error, :cancelled} =
             DBConnection.transaction(pool, fn connection ->
               Driver.query!(connection, "insert into events values (2)")
               DBConnection.rollback(connection, :cancelled)
             end)

    assert %DBResult{rows: [[1]]} =
             Driver.query!(pool, "select count(*) from events")
  end

  test "re-prepares a cached query after timeout replacement", %{pool: pool} do
    query = %Query{statement: "select 42 as answer"}

    assert {:ok, prepared, %DBResult{rows: [[42]]}} =
             DBConnection.prepare_execute(pool, query, [])

    assert {:error, _error} =
             Driver.query(
               pool,
               "select sum(value) from range(1000000000) values_table(value)",
               [],
               timeout: 20
             )

    assert {:ok, %Query{}, %DBResult{rows: [[42]]}} =
             DBConnection.execute(pool, prepared, [])
  end
end
