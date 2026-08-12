defmodule Kinda.SQLite do
  @moduledoc """
  Synchronous SQLite driver API backed by a Kinda NIF.

  Connections and prepared statements are explicit resources. All operations
  return tagged tuples suitable for use from a `DBConnection` implementation.
  """

  alias Kinda.SQLite.{Blob, Database, Error, Native, Result, Statement}

  @type value :: nil | boolean() | integer() | float() | binary() | Blob.t()

  @spec open(Path.t()) :: {:ok, Database.t()} | {:error, Error.t()}
  def open(path \\ ":memory:") when is_binary(path) do
    {:ok, %Database{resource: Native.open(path), path: path}}
  rescue
    error in Kinda.CallError -> {:error, Error.from_call(error, :open)}
  end

  @spec open_memory() :: {:ok, Database.t()} | {:error, Error.t()}
  def open_memory, do: open(":memory:")

  @spec close(Database.t() | Statement.t()) :: :ok
  def close(%Database{resource: resource}) do
    :ok = Native.close(resource)
  end

  def close(%Statement{resource: resource}) do
    :ok = Native.finalize(resource)
  end

  @spec prepare(Database.t(), iodata()) :: {:ok, Statement.t()} | {:error, Error.t()}
  def prepare(%Database{} = database, sql) do
    sql = IO.iodata_to_binary(sql)
    resource = Native.prepare(database.resource, sql)
    {:ok, %Statement{resource: resource, database: database, sql: sql}}
  rescue
    error in Kinda.CallError -> {:error, database_error(database, error, :prepare, sql)}
  end

  @spec query(Database.t(), iodata(), [value()]) :: {:ok, Result.t()} | {:error, Error.t()}
  def query(%Database{} = database, sql, params \\ []) when is_list(params) do
    with {:ok, statement} <- prepare(database, sql) do
      try do
        execute(statement, params)
      after
        close(statement)
      end
    end
  end

  @spec execute(Statement.t(), [value()]) :: {:ok, Result.t()} | {:error, Error.t()}
  def execute(%Statement{} = statement, params \\ []) when is_list(params) do
    with :ok <- reset(statement),
         :ok <- bind(statement, params) do
      columns = column_names(statement)

      case collect_rows(statement, []) do
        {:ok, rows} ->
          {:ok, build_result(statement.database, columns, rows)}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @spec reset(Statement.t()) :: :ok | {:error, Error.t()}
  def reset(%Statement{} = statement) do
    :ok = Native.reset(statement.resource)
    :ok = Native.clear_bindings(statement.resource)
  rescue
    error in Kinda.CallError ->
      {:error, database_error(statement.database, error, :reset, statement.sql)}
  end

  @spec bind(Statement.t(), [value()]) :: :ok | {:error, Error.t()}
  def bind(%Statement{} = statement, params) do
    params
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case bind_value(statement.resource, index, value) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  rescue
    error in Kinda.CallError ->
      {:error, database_error(statement.database, error, :bind, statement.sql)}
  end

  @spec interrupt(Database.t()) :: :ok
  def interrupt(%Database{resource: resource}), do: Native.interrupt(resource)

  @spec changes(Database.t()) :: non_neg_integer()
  def changes(%Database{resource: resource}), do: Native.database_changes(resource)

  @spec last_insert_rowid(Database.t()) :: integer()
  def last_insert_rowid(%Database{resource: resource}), do: Native.last_insert_rowid(resource)

  @spec sqlite_version() :: String.t()
  def sqlite_version, do: Native.sqlite_version()

  defp bind_value(resource, index, nil), do: Native.bind_null(resource, index)
  defp bind_value(resource, index, false), do: Native.bind_int64(resource, index, 0)
  defp bind_value(resource, index, true), do: Native.bind_int64(resource, index, 1)

  defp bind_value(resource, index, value) when is_integer(value),
    do: Native.bind_int64(resource, index, value)

  defp bind_value(resource, index, value) when is_float(value),
    do: Native.bind_double(resource, index, value)

  defp bind_value(resource, index, value) when is_binary(value),
    do: Native.bind_text(resource, index, value)

  defp bind_value(resource, index, %Blob{data: value}),
    do: Native.bind_blob(resource, index, value)

  defp bind_value(_resource, _index, value) do
    {:error,
     %Error{
       message: "unsupported SQLite parameter: #{inspect(value)}",
       operation: :bind,
       code: :unsupported_parameter
     }}
  end

  defp collect_rows(statement, rows) do
    case Native.step(statement.resource) do
      :row -> collect_rows(statement, [read_row(statement) | rows])
      :done -> {:ok, Enum.reverse(rows)}
      :error -> {:error, database_error(statement.database, nil, :step, statement.sql)}
    end
  rescue
    error in Kinda.CallError ->
      {:error, database_error(statement.database, error, :step, statement.sql)}
  end

  defp column_names(statement) do
    count = Native.column_count(statement.resource)
    for index <- indices(count), do: Native.column_name(statement.resource, index)
  end

  defp read_row(statement) do
    count = Native.column_count(statement.resource)
    for index <- indices(count), do: read_column(statement.resource, index)
  end

  defp read_column(resource, index) do
    case Native.column_type(resource, index) do
      :null -> nil
      :integer -> Native.column_int64(resource, index)
      :float -> Native.column_double(resource, index)
      :text -> Native.column_text(resource, index)
      :blob -> %Blob{data: Native.column_blob(resource, index)}
    end
  end

  defp indices(0), do: []
  defp indices(count), do: 0..(count - 1)

  defp build_result(database, [], rows) do
    %Result{columns: [], rows: rows, num_rows: changes(database)}
  end

  defp build_result(_database, columns, rows) do
    %Result{columns: columns, rows: rows, num_rows: length(rows)}
  end

  defp database_error(database, call_error, operation, sql) do
    {code, extended_code, message} = Native.error_info(database.resource)

    %Error{
      message: message,
      code: code,
      extended_code: extended_code,
      operation: operation,
      sql: sql,
      call_error: call_error
    }
  rescue
    _ -> Error.from_call(call_error, operation, sql)
  end
end
