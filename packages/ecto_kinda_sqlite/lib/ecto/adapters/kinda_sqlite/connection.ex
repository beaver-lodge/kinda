defmodule Ecto.Adapters.KindaSQLite.Connection do
  @moduledoc false

  @behaviour Ecto.Adapters.SQL.Connection

  alias Ecto.Adapters.SQL
  alias Kinda.SQLite
  alias Kinda.SQLite.{Error, Query, Result}

  @dialect Ecto.Adapters.SQLite3.Connection

  @impl Ecto.Adapters.SQL.Connection
  def child_spec(options) do
    {:ok, _applications} = Application.ensure_all_started(:db_connection)

    options
    |> normalize_options()
    |> SQLite.Connection.child_spec()
  end

  @impl Ecto.Adapters.SQL.Connection
  def prepare_execute(connection, name, statement, params, options) do
    query = %Query{name: name, statement: IO.iodata_to_binary(statement)}

    connection
    |> DBConnection.prepare_execute(query, params, options)
    |> normalize_result()
  end

  @impl Ecto.Adapters.SQL.Connection
  def execute(connection, %Query{prepared: nil, statement: statement}, params, options) do
    execute(connection, statement, params, options)
  end

  def execute(connection, %Query{} = query, params, options) do
    connection
    |> DBConnection.execute(query, params, options)
    |> normalize_result()
  end

  def execute(connection, statement, params, options)
      when is_binary(statement) or is_list(statement) do
    query = %Query{statement: IO.iodata_to_binary(statement)}

    case DBConnection.prepare_execute(connection, query, params, options) do
      {:ok, _query, result} -> {:ok, normalize_result(result)}
      {:error, error} -> {:error, error}
    end
  end

  @impl Ecto.Adapters.SQL.Connection
  def query(connection, statement, params, options) do
    case SQLite.Connection.query(connection, statement, params, options) do
      {:ok, result} -> {:ok, normalize_result(result)}
      {:error, error} -> {:error, error}
    end
  end

  @impl Ecto.Adapters.SQL.Connection
  def query_many(_connection, _statement, _params, _options) do
    raise RuntimeError, "query_many is not supported by SQLite"
  end

  @impl Ecto.Adapters.SQL.Connection
  def stream(connection, statement, params, options) do
    SQLite.Connection.stream(connection, statement, params, options)
  end

  @impl Ecto.Adapters.SQL.Connection
  def to_constraints(%Error{message: "UNIQUE constraint failed: " <> columns}, _options) do
    [unique: constraint_name(columns)]
  end

  def to_constraints(%Error{message: "FOREIGN KEY constraint failed"}, _options) do
    [foreign_key: nil]
  end

  def to_constraints(%Error{message: "CHECK constraint failed: " <> name}, _options) do
    [check: name]
  end

  def to_constraints(_error, _options), do: []

  @impl Ecto.Adapters.SQL.Connection
  defdelegate all(query), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  defdelegate update_all(query), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  defdelegate delete_all(query), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  def insert(prefix, table, header, rows, on_conflict, returning, placeholders, options) do
    @dialect.insert(
      prefix,
      table,
      header,
      rows,
      on_conflict,
      returning,
      placeholders,
      options
    )
  end

  def insert(prefix, table, header, rows, on_conflict, returning, placeholders) do
    insert(prefix, table, header, rows, on_conflict, returning, placeholders, [])
  end

  @impl Ecto.Adapters.SQL.Connection
  defdelegate update(prefix, table, fields, filters, returning), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  defdelegate delete(prefix, table, filters, returning), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  def explain_query(connection, query, params, options) do
    type = Keyword.get(options, :type, :query_plan)
    prefix = if type == :instructions, do: "EXPLAIN ", else: "EXPLAIN QUERY PLAN "

    case query(connection, prefix <> query, params, options) do
      {:ok, %Result{} = result} -> {:ok, SQL.format_table(result)}
      error -> error
    end
  end

  @impl Ecto.Adapters.SQL.Connection
  defdelegate execute_ddl(command), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  defdelegate ddl_logs(result), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  defdelegate table_exists_query(table), to: @dialect

  defp normalize_options(options) do
    database = if options[:database] == :memory, do: ":memory:", else: options[:database]
    Keyword.put(options, :database, database)
  end

  defp normalize_result({:ok, query, result}), do: {:ok, query, normalize_result(result)}
  defp normalize_result({:ok, result}), do: {:ok, normalize_result(result)}
  defp normalize_result({:error, error}), do: {:error, error}

  defp normalize_result(%Result{columns: [], rows: []} = result) do
    %{result | rows: nil}
  end

  defp normalize_result(result), do: result

  defp constraint_name(columns) do
    columns
    |> String.split(", ")
    |> Enum.map_join("_", &String.replace(&1, ".", "_"))
    |> Kernel.<>("_index")
  end
end
