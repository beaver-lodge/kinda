defmodule Kinda.DuckDBPendingTest do
  use ExUnit.Case, async: true

  alias Kinda.DuckDB
  alias Kinda.DuckDB.Result

  setup do
    database = DuckDB.open()
    connection = DuckDB.connect(database)
    on_exit(fn -> DuckDB.close(connection) end)
    on_exit(fn -> DuckDB.close(database) end)
    %{connection: connection, database: database}
  end

  test "executes a parameterized query incrementally", %{connection: connection} do
    prepared = DuckDB.prepare(connection, "select ?::bigint + ?::bigint as total")
    pending = DuckDB.pending(prepared, [40, 2])

    assert %Result{columns: [%{name: "total", values: [42]}]} =
             pending |> DuckDB.execute_pending() |> DuckDB.materialize()

    :ok = DuckDB.close(pending)
    :ok = DuckDB.close(prepared)
  end

  test "pending query survives arbitrary parent close order", %{
    connection: connection,
    database: database
  } do
    prepared = DuckDB.prepare(connection, "select 42 as answer")
    pending = DuckDB.pending(prepared)

    :ok = DuckDB.close(database)
    :ok = DuckDB.close(connection)
    :ok = DuckDB.close(prepared)

    borrowed = DuckDB.execute_pending(pending)
    :ok = DuckDB.close(pending)

    assert %Result{columns: [%{name: "answer", values: [42]}]} =
             DuckDB.materialize(borrowed)

    :ok = DuckDB.close(borrowed)
  end

  test "pending query retains parents across wrapper garbage collection", %{
    connection: connection
  } do
    pending = connection |> DuckDB.prepare("select 7 as value") |> DuckDB.pending()
    :erlang.garbage_collect(self())

    assert %Result{columns: [%{values: [7]}]} =
             pending |> DuckDB.execute_pending() |> DuckDB.materialize()
  end
end
