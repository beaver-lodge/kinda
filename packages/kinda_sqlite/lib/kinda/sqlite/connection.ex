defmodule Kinda.SQLite.Connection do
  @moduledoc """
  `DBConnection` implementation for `Kinda.SQLite`.

  The `:database` option selects a file path and defaults to `":memory:"`.
  Each pool worker owns one SQLite connection.
  """

  use DBConnection

  alias Kinda.SQLite
  alias Kinda.SQLite.{Cursor, Query, Result}

  @type state :: %{database: Kinda.SQLite.Database.t(), transaction_status: DBConnection.status()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: DBConnection.start_link(__MODULE__, opts)

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts), do: DBConnection.child_spec(__MODULE__, opts)

  @spec query(DBConnection.conn(), iodata(), [SQLite.value()], keyword()) ::
          {:ok, Result.t()} | {:error, Exception.t()}
  def query(connection, statement, params \\ [], opts \\ []) do
    query = %Query{statement: IO.iodata_to_binary(statement)}

    case DBConnection.prepare_execute(connection, query, params, opts) do
      {:ok, _query, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  @spec query!(DBConnection.conn(), iodata(), [SQLite.value()], keyword()) :: Result.t()
  def query!(connection, statement, params \\ [], opts \\ []) do
    case query(connection, statement, params, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @spec stream(DBConnection.conn(), iodata(), [SQLite.value()], keyword()) :: Enumerable.t()
  def stream(connection, statement, params \\ [], opts \\ []) do
    query = %Query{statement: IO.iodata_to_binary(statement)}
    DBConnection.prepare_stream(connection, query, params, opts)
  end

  @impl DBConnection
  def connect(opts) do
    path = Keyword.get(opts, :database, ":memory:")

    case SQLite.open(path) do
      {:ok, database} -> configure(database)
      {:error, error} -> {:error, error}
    end
  end

  @impl DBConnection
  def disconnect(_error, %{database: database}) do
    SQLite.interrupt(database)
    SQLite.close(database)
  end

  @impl DBConnection
  def checkout(state), do: {:ok, state}

  @impl DBConnection
  def ping(%{database: database} = state) do
    case SQLite.query(database, "SELECT 1") do
      {:ok, _result} -> {:ok, state}
      {:error, error} -> {:disconnect, error, state}
    end
  end

  @impl DBConnection
  def handle_prepare(%Query{statement: sql} = query, _opts, %{database: database} = state) do
    case SQLite.prepare(database, sql) do
      {:ok, statement} -> {:ok, %{query | prepared: statement}, state}
      {:error, error} -> {:error, error, mark_failed(state)}
    end
  end

  @impl DBConnection
  def handle_execute(%Query{prepared: statement} = query, params, _opts, state) do
    case SQLite.execute(statement, params) do
      {:ok, result} -> {:ok, query, result, state}
      {:error, error} -> {:error, error, mark_failed(state)}
    end
  end

  @impl DBConnection
  def handle_close(%Query{prepared: nil}, _opts, state) do
    {:ok, %Result{columns: [], rows: [], num_rows: 0}, state}
  end

  def handle_close(%Query{prepared: statement}, _opts, state) do
    :ok = SQLite.close(statement)
    {:ok, %Result{columns: [], rows: [], num_rows: 0}, state}
  end

  @impl DBConnection
  def handle_begin(_opts, %{transaction_status: :idle} = state) do
    transaction_command(state, "BEGIN", :transaction)
  end

  def handle_begin(_opts, state), do: {state.transaction_status, state}

  @impl DBConnection
  def handle_commit(_opts, %{transaction_status: :transaction} = state) do
    transaction_command(state, "COMMIT", :idle)
  end

  def handle_commit(_opts, state), do: {state.transaction_status, state}

  @impl DBConnection
  def handle_rollback(_opts, %{transaction_status: status} = state)
      when status in [:transaction, :error] do
    transaction_command(state, "ROLLBACK", :idle)
  end

  def handle_rollback(_opts, state), do: {state.transaction_status, state}

  @impl DBConnection
  def handle_status(_opts, state), do: {state.transaction_status, state}

  @impl DBConnection
  def handle_declare(query, params, _opts, state) do
    case SQLite.declare(query.prepared, params) do
      {:ok, columns} ->
        {:ok, query, %Cursor{columns: columns, statement: query.prepared}, state}

      {:error, error} ->
        {:error, error, mark_failed(state)}
    end
  end

  @impl DBConnection
  def handle_fetch(_query, %Cursor{columns: columns, statement: statement}, opts, state) do
    max_rows = Keyword.get(opts, :max_rows, 500)

    case SQLite.fetch(statement, columns, max_rows) do
      {:cont, result} -> {:cont, result, state}
      {:halt, result} -> {:halt, result, state}
      {:error, error} -> {:error, error, mark_failed(state)}
    end
  end

  @impl DBConnection
  def handle_deallocate(_query, _cursor, _opts, state) do
    {:ok, %Result{columns: [], rows: [], num_rows: 0}, state}
  end

  defp transaction_command(%{database: database} = state, sql, next_status) do
    case SQLite.query(database, sql) do
      {:ok, result} ->
        {:ok, result, %{state | transaction_status: next_status}}

      {:error, error} ->
        {:disconnect, error, state}
    end
  end

  defp configure(database) do
    case SQLite.query(database, "PRAGMA foreign_keys = ON") do
      {:ok, _result} ->
        {:ok, %{database: database, transaction_status: :idle}}

      {:error, error} ->
        SQLite.close(database)
        {:error, error}
    end
  end

  defp mark_failed(%{transaction_status: :transaction} = state),
    do: %{state | transaction_status: :error}

  defp mark_failed(state), do: state
end
