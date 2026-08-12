defmodule Kinda.DuckDB.DBConnection do
  @moduledoc """
  `DBConnection` implementation using DuckDB prepared and pending queries.

  Pending work is advanced one native task per NIF call so DBConnection can
  interrupt and replace a connection when a client exits or times out.
  """

  use DBConnection

  alias Kinda.DuckDB
  alias Kinda.DuckDB.{Cursor, DBResult, Query}

  @type state :: %{
          database: DuckDB.Database.t(),
          connection: DuckDB.Connection.t(),
          transaction_status: DBConnection.status()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: DBConnection.start_link(__MODULE__, options)

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options), do: DBConnection.child_spec(__MODULE__, options)

  @spec query(DBConnection.conn(), iodata(), [DuckDB.value()], keyword()) ::
          {:ok, DBResult.t()} | {:error, Exception.t()}
  def query(connection, statement, params \\ [], options \\ []) do
    query = %Query{statement: IO.iodata_to_binary(statement)}

    case DBConnection.prepare_execute(connection, query, params, options) do
      {:ok, _query, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  @spec query!(DBConnection.conn(), iodata(), [DuckDB.value()], keyword()) :: DBResult.t()
  def query!(connection, statement, params \\ [], options \\ []) do
    case query(connection, statement, params, options) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @spec stream(DBConnection.conn(), iodata(), [DuckDB.value()], keyword()) :: Enumerable.t()
  def stream(connection, statement, params \\ [], options \\ []) do
    query = %Query{statement: IO.iodata_to_binary(statement)}
    DBConnection.prepare_stream(connection, query, params, options)
  end

  @impl DBConnection
  def connect(options) do
    database = DuckDB.open(Keyword.get(options, :database, ":memory:"))
    connection = DuckDB.connect(database)
    {:ok, %{database: database, connection: connection, transaction_status: :idle}}
  rescue
    error -> {:error, error}
  end

  @impl DBConnection
  def disconnect(_error, state) do
    DuckDB.interrupt(state.connection)
    DuckDB.close(state.connection)
    DuckDB.close(state.database)
  end

  @impl DBConnection
  def checkout(state), do: {:ok, state}

  @impl DBConnection
  def ping(state) do
    case execute_sql(state.connection, "select 1", []) do
      {:ok, _result} -> {:ok, state}
      {:error, error} -> {:disconnect, error, state}
    end
  end

  @impl DBConnection
  def handle_prepare(%Query{} = query, _options, state) do
    prepared = DuckDB.prepare(state.connection, query.statement)
    {:ok, %{query | prepared: prepared}, state}
  rescue
    error -> {:error, error, mark_failed(state)}
  end

  @impl DBConnection
  def handle_execute(%Query{} = query, params, _options, state) do
    with {:ok, query} <- localize(query, state.connection),
         {:ok, result} <- execute_prepared(query.prepared, params) do
      {:ok, query, result, state}
    else
      {:error, error} -> {:error, error, mark_failed(state)}
    end
  end

  @impl DBConnection
  def handle_close(%Query{prepared: nil}, _options, state), do: {:ok, empty_result(), state}

  def handle_close(%Query{prepared: prepared}, _options, state) do
    if prepared.connection.resource == state.connection.resource, do: DuckDB.close(prepared)
    {:ok, empty_result(), state}
  end

  @impl DBConnection
  def handle_begin(_options, %{transaction_status: :idle} = state) do
    transaction_command(state, "BEGIN TRANSACTION", :transaction)
  end

  def handle_begin(_options, state), do: {state.transaction_status, state}

  @impl DBConnection
  def handle_commit(_options, %{transaction_status: :transaction} = state) do
    transaction_command(state, "COMMIT", :idle)
  end

  def handle_commit(_options, state), do: {state.transaction_status, state}

  @impl DBConnection
  def handle_rollback(_options, %{transaction_status: status} = state)
      when status in [:transaction, :error] do
    transaction_command(state, "ROLLBACK", :idle)
  end

  def handle_rollback(_options, state), do: {state.transaction_status, state}

  @impl DBConnection
  def handle_status(_options, state), do: {state.transaction_status, state}

  @impl DBConnection
  def handle_declare(query, params, _options, state) do
    case handle_execute(query, params, [], state) do
      {:ok, query, %DBResult{columns: columns, rows: rows}, state} ->
        cursor = %Cursor{columns: columns, ref: make_ref()}
        Process.put(cursor_key(cursor), rows || [])
        {:ok, query, cursor, state}

      {:error, error, state} ->
        {:error, error, state}
    end
  end

  @impl DBConnection
  def handle_fetch(_query, %Cursor{columns: columns} = cursor, options, state) do
    rows = Process.get(cursor_key(cursor), [])
    {batch, rest} = Enum.split(rows, Keyword.get(options, :max_rows, 500))
    result = %DBResult{columns: columns, rows: batch, num_rows: length(batch)}

    if rest == [] do
      Process.delete(cursor_key(cursor))
      {:halt, result, state}
    else
      Process.put(cursor_key(cursor), rest)
      {:cont, result, state}
    end
  end

  @impl DBConnection
  def handle_deallocate(_query, cursor, _options, state) do
    Process.delete(cursor_key(cursor))
    {:ok, empty_result(), state}
  end

  defp localize(%Query{prepared: nil} = query, connection), do: prepare_local(query, connection)

  defp localize(%Query{prepared: prepared} = query, connection) do
    if prepared.connection.resource == connection.resource do
      {:ok, query}
    else
      prepare_local(query, connection)
    end
  end

  defp prepare_local(query, connection) do
    {:ok, %{query | prepared: DuckDB.prepare(connection, query.statement)}}
  rescue
    error -> {:error, error}
  end

  defp execute_sql(connection, sql, params) do
    prepared = DuckDB.prepare(connection, sql)

    try do
      execute_prepared(prepared, params)
    after
      DuckDB.close(prepared)
    end
  rescue
    error -> {:error, error}
  end

  defp execute_prepared(prepared, params) do
    pending = DuckDB.pending(prepared, params)

    try do
      borrowed = DuckDB.execute_pending(pending)

      try do
        {:ok, row_result(DuckDB.materialize(borrowed))}
      after
        DuckDB.close(borrowed)
      end
    after
      DuckDB.close(pending)
    end
  rescue
    error -> {:error, error}
  end

  defp transaction_command(state, sql, next_status) do
    case execute_sql(state.connection, sql, []) do
      {:ok, result} -> {:ok, result, %{state | transaction_status: next_status}}
      {:error, error} -> {:disconnect, error, state}
    end
  end

  defp row_result(%DuckDB.Result{columns: columns, row_count: count, rows_changed: changed}) do
    names = Enum.map(columns, & &1.name)
    values = Enum.map(columns, & &1.values)
    rows = if values == [], do: nil, else: values |> Enum.zip() |> Enum.map(&Tuple.to_list/1)
    %DBResult{columns: names, rows: rows, num_rows: if(names == [], do: changed, else: count)}
  end

  defp empty_result, do: %DBResult{columns: [], rows: nil, num_rows: 0}

  defp cursor_key(%Cursor{ref: ref}), do: {__MODULE__, ref}

  defp mark_failed(%{transaction_status: :transaction} = state),
    do: %{state | transaction_status: :error}

  defp mark_failed(state), do: state
end
