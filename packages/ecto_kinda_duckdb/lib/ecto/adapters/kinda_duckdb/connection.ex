defmodule Ecto.Adapters.KindaDuckDB.Connection do
  @moduledoc false

  @behaviour Ecto.Adapters.SQL.Connection

  alias Ecto.Adapters.SQL
  alias Kinda.DuckDB
  alias Kinda.DuckDB.{DBResult, Error, Query}

  @dialect Ecto.Adapters.Postgres.Connection
  @unsupported "is not supported by the experimental DuckDB Ecto adapter"

  @impl Ecto.Adapters.SQL.Connection
  def child_spec(options) do
    {:ok, _applications} = Application.ensure_all_started(:db_connection)

    options
    |> normalize_options()
    |> DuckDB.DBConnection.child_spec()
  end

  @impl Ecto.Adapters.SQL.Connection
  def prepare_execute(connection, name, statement, params, options) do
    query = %Query{name: name, statement: IO.iodata_to_binary(statement)}
    DBConnection.prepare_execute(connection, query, params, options)
  end

  @impl Ecto.Adapters.SQL.Connection
  def execute(connection, %Query{prepared: nil, statement: statement}, params, options) do
    execute(connection, statement, params, options)
  end

  def execute(connection, %Query{} = query, params, options) do
    DBConnection.execute(connection, query, params, options)
  end

  def execute(connection, statement, params, options)
      when is_binary(statement) or is_list(statement) do
    query = %Query{statement: IO.iodata_to_binary(statement)}

    case DBConnection.prepare_execute(connection, query, params, options) do
      {:ok, _query, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  @impl Ecto.Adapters.SQL.Connection
  def query(connection, statement, params, options) do
    DuckDB.DBConnection.query(connection, statement, params, options)
  end

  @impl Ecto.Adapters.SQL.Connection
  def query_many(_connection, _statement, _params, _options) do
    raise ArgumentError, "query_many #{@unsupported}"
  end

  @impl Ecto.Adapters.SQL.Connection
  def stream(connection, statement, params, options) do
    DuckDB.DBConnection.stream(connection, statement, params, options)
  end

  @impl Ecto.Adapters.SQL.Connection
  def to_constraints(_error, _options), do: []

  @impl Ecto.Adapters.SQL.Connection
  defdelegate all(query), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  def update_all(_query), do: unsupported!(:update_all)

  @impl Ecto.Adapters.SQL.Connection
  def delete_all(_query), do: unsupported!(:delete_all)

  @impl Ecto.Adapters.SQL.Connection
  defdelegate insert(prefix, table, header, rows, on_conflict, returning, placeholders, options),
    to: @dialect

  defdelegate insert(prefix, table, header, rows, on_conflict, returning, placeholders),
    to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  defdelegate update(prefix, table, fields, filters, returning), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  defdelegate delete(prefix, table, filters, returning), to: @dialect

  @impl Ecto.Adapters.SQL.Connection
  def explain_query(connection, query, params, options) do
    case query(connection, "EXPLAIN " <> query, params, options) do
      {:ok, %DBResult{} = result} -> {:ok, SQL.format_table(result)}
      error -> error
    end
  end

  @impl Ecto.Adapters.SQL.Connection
  def execute_ddl(_command), do: unsupported!(:migration)

  @impl Ecto.Adapters.SQL.Connection
  def ddl_logs(_result), do: []

  @impl Ecto.Adapters.SQL.Connection
  def table_exists_query(table) do
    {"SELECT 1 FROM information_schema.tables WHERE table_name = $1 LIMIT 1", [table]}
  end

  defp normalize_options(options) do
    database = if options[:database] == :memory, do: ":memory:", else: options[:database]
    Keyword.put(options, :database, database)
  end

  defp unsupported!(operation) do
    raise Error, message: "#{operation} #{@unsupported}", operation: operation
  end
end
