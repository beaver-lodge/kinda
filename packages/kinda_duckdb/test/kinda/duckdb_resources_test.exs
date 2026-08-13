defmodule Kinda.DuckDBResourcesTest do
  use ExUnit.Case, async: true

  alias Kinda.DuckDB
  alias Kinda.DuckDB.{BorrowedResult, Result}
  alias Kinda.DuckDB.Native
  alias Kinda.Testing.{Isolated, NativeScenario}

  setup do
    database = DuckDB.open()
    connection = DuckDB.connect(database)
    on_exit(fn -> DuckDB.close(connection) end)
    on_exit(fn -> DuckDB.close(database) end)
    %{connection: connection, database: database}
  end

  test "materializes safe BEAM-owned columnar results", %{connection: connection} do
    assert %Result{
             columns: [
               %{name: "id", values: [1, 2]},
               %{name: "name", values: ["one", "two"]},
               %{name: "active", values: [true, false]},
               %{name: "score", values: [1.5, 2.5]},
               %{name: "missing", values: [nil, nil]}
             ],
             row_count: 2
           } =
             DuckDB.query(
               connection,
               """
               select *
               from (values
                 (1::bigint, 'one', true, 1.5::double, null),
                 (2::bigint, 'two', false, 2.5::double, null)
               ) values_table(id, name, active, score, missing)
               """
             )
  end

  test "borrowed results survive arbitrary parent close order", %{
    connection: connection,
    database: database
  } do
    assert %BorrowedResult{} = borrowed = DuckDB.query_borrowed(connection, "select 42 as answer")

    :ok = DuckDB.close(database)
    :ok = DuckDB.close(connection)

    assert %Result{columns: [%{name: "answer", values: [42]}]} =
             DuckDB.materialize(borrowed)

    :ok = DuckDB.close(borrowed)
    :ok = DuckDB.close(borrowed)
  end

  test "Appender retains its connection and bulk appends typed rows", %{
    connection: connection,
    database: database
  } do
    DuckDB.query(
      connection,
      "create table metrics(id bigint, name varchar, active boolean, score double)"
    )

    appender = DuckDB.create_appender(connection, "metrics")
    :ok = DuckDB.append(appender, [1, "one", true, 1.5])
    :ok = DuckDB.append(appender, [2, "two", false, nil])
    :ok = DuckDB.flush(appender)

    assert %Result{
             columns: [
               %{name: "id", values: [1, 2]},
               %{name: "name", values: ["one", "two"]},
               %{name: "active", values: [true, false]},
               %{name: "score", values: [1.5, nil]}
             ]
           } = DuckDB.query(connection, "select * from metrics order by id")

    :ok = DuckDB.close(database)
    :ok = DuckDB.close(connection)
    :ok = DuckDB.close(appender)
    :ok = DuckDB.close(appender)
  end

  test "resources remain isolated from SQLite NIF resources", %{connection: connection} do
    sqlite = Kinda.SQLite.open_memory() |> elem(1)
    assert %{columns: [%{values: [42]}]} = DuckDB.query(connection, "select 42")
    assert {:ok, %{rows: [[42]]}} = Kinda.SQLite.query(sqlite, "select 42")
    assert %Kinda.CallError{} = catch_error(Native.query(sqlite.resource, "select 42"))
    :ok = Kinda.SQLite.close(sqlite)
  end

  test "resources survive parent wrapper garbage collection", %{connection: connection} do
    borrowed = DuckDB.query_borrowed(connection, "select 7 as value")
    connection = nil
    _database = nil
    :erlang.garbage_collect(self())

    assert connection == nil
    assert %{columns: [%{values: [7]}]} = DuckDB.materialize(borrowed)
  end

  test "borrowed resources survive a NIF hot upgrade" do
    expected = %Result{
      columns: [%{name: "answer", values: [42]}],
      row_count: 1,
      rows_changed: 0
    }

    steps = [
      {:call, :database, {DuckDB, :open, []}},
      {:call, :connection, {DuckDB, :connect, [{:resource, :database}]}},
      {:call, :borrowed,
       {DuckDB, :query_borrowed, [{:resource, :connection}, "select 42 as answer"]}},
      {:upgrade, Native, :kinda_duckdb, "KindaDuckDBNIF"},
      {:purge, Native},
      {:expect, expected, {DuckDB, :materialize, [{:resource, :borrowed}]}}
    ]

    assert Isolated.run({NativeScenario, :run, [steps]}, timeout: 120_000) == :ok
  end
end
