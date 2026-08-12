defmodule Kinda.SQLite.ConnectionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Kinda.SQLite
  alias Kinda.SQLite.{Connection, Error, Query, Result}

  setup do
    start_supervised!(
      {Connection, database: ":memory:", pool_size: 1, name: __MODULE__, backoff_type: :stop}
    )

    :ok
  end

  test "runs parameterized queries through DBConnection" do
    assert %Result{} = Connection.query!(__MODULE__, "create table items(id integer, name text)")

    assert %{num_rows: 1} =
             Connection.query!(__MODULE__, "insert into items values (?, ?)", [1, "one"])

    assert %{columns: ["id", "name"], rows: [[1, "one"]]} =
             Connection.query!(__MODULE__, "select id, name from items")
  end

  test "prepares, reuses, and explicitly closes statements" do
    query = %Query{statement: "select ? + 1"}
    assert {:ok, prepared} = DBConnection.prepare(__MODULE__, query)
    assert {:ok, ^prepared, %{rows: [[2]]}} = DBConnection.execute(__MODULE__, prepared, [1])
    assert {:ok, ^prepared, %{rows: [[3]]}} = DBConnection.execute(__MODULE__, prepared, [2])
    assert {:ok, %Result{}} = DBConnection.close(__MODULE__, prepared)
  end

  test "commits and rolls back transactions" do
    Connection.query!(__MODULE__, "create table events(id integer)")

    assert {:ok, :committed} =
             DBConnection.transaction(__MODULE__, fn connection ->
               Connection.query!(connection, "insert into events values (1)")
               :committed
             end)

    assert {:error, :rolled_back} =
             DBConnection.transaction(__MODULE__, fn connection ->
               Connection.query!(connection, "insert into events values (2)")
               DBConnection.rollback(connection, :rolled_back)
             end)

    assert %{rows: [[1]]} = Connection.query!(__MODULE__, "select id from events order by id")
  end

  test "streams bounded result batches" do
    result =
      DBConnection.run(__MODULE__, fn connection ->
        connection
        |> Connection.stream("select value from json_each('[1,2,3,4,5]') order by value", [],
          max_rows: 2
        )
        |> Enum.to_list()
      end)

    assert Enum.map(result, & &1.rows) == [[[1], [2]], [[3], [4]], [[5]]]
  end

  test "interrupts timed out native work and reconnects" do
    sql = """
    WITH RECURSIVE count(x) AS (
      VALUES(0)
      UNION ALL
      SELECT x + 1 FROM count WHERE x < 1000000000
    )
    SELECT sum(x) FROM count
    """

    capture_log(fn ->
      assert {:error, %Error{operation: :step}} =
               Connection.query(__MODULE__, sql, [], timeout: 10)
    end)

    assert %{rows: [[1]]} = Connection.query!(__MODULE__, "select 1")
  end

  test "savepoint callbacks preserve their outer transaction" do
    {:ok, database} = SQLite.open_memory()
    state = %{database: database, transaction_status: :idle}

    assert {:ok, _result, state} = Connection.handle_begin([], state)
    assert {:ok, _result} = SQLite.query(database, "create table values_table(value integer)")
    assert {:ok, _result} = SQLite.query(database, "insert into values_table values (1)")

    assert {:ok, _result, state} = Connection.handle_begin([mode: :savepoint], state)
    assert {:ok, _result} = SQLite.query(database, "insert into values_table values (2)")
    assert {:ok, _result, state} = Connection.handle_rollback([mode: :savepoint], state)
    assert state.transaction_status == :transaction

    assert {:ok, _result, state} = Connection.handle_commit([], state)
    assert state.transaction_status == :idle
    assert {:ok, %{rows: [[1]]}} = SQLite.query(database, "select value from values_table")

    :ok = SQLite.close(database)
  end

  @tag :tmp_dir
  test "shares a file database across pooled connections", %{tmp_dir: tmp_dir} do
    database = Path.join(tmp_dir, "pool.sqlite3")

    pool =
      start_supervised!({Connection, database: database, pool_size: 2}, id: :file_database_pool)

    Connection.query!(pool, "create table pooled_items(id integer primary key)")
    Connection.query!(pool, "insert into pooled_items values (42)")

    rows =
      1..8
      |> Task.async_stream(fn _ -> Connection.query!(pool, "select id from pooled_items") end)
      |> Enum.map(fn {:ok, result} -> result.rows end)

    assert Enum.uniq(rows) == [[[42]]]

    query = %Query{statement: "select id from pooled_items"}
    assert {:ok, prepared} = DBConnection.prepare(pool, query)

    rows =
      for _index <- 1..8 do
        assert {:ok, _localized, result} = DBConnection.execute(pool, prepared, [])
        result.rows
      end

    assert Enum.uniq(rows) == [[[42]]]
  end
end
