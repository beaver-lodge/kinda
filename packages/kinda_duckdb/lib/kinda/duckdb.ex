defmodule Kinda.DuckDB do
  @moduledoc """
  DuckDB driver with explicit resources and BEAM-owned columnar results.

  `query/2` copies values into immutable BEAM terms. Use `query_borrowed/2`
  only when incremental access to the resource-backed native result is useful.
  """

  alias Kinda.DuckDB.{
    Appender,
    BorrowedResult,
    Connection,
    Database,
    Error,
    Native,
    Pending,
    Prepared,
    Result
  }

  @type value :: nil | boolean() | integer() | float() | binary()

  @spec library_version() :: String.t()
  def library_version, do: Native.library_version()

  @spec open(Path.t()) :: Database.t()
  def open(path \\ ":memory:") do
    %Database{resource: Native.open(path), path: path}
  end

  @spec connect(Database.t()) :: Connection.t()
  def connect(%Database{} = database) do
    %Connection{resource: Native.connect(database.resource), database: database}
  end

  @spec close(
          Database.t()
          | Connection.t()
          | BorrowedResult.t()
          | Appender.t()
          | Prepared.t()
          | Pending.t()
        ) :: :ok
  def close(%Database{resource: resource}), do: Native.close_database(resource)
  def close(%Connection{resource: resource}), do: Native.close_connection(resource)
  def close(%BorrowedResult{resource: resource}), do: Native.close_result(resource)
  def close(%Appender{resource: resource}), do: Native.close_appender(resource)
  def close(%Prepared{resource: resource}), do: Native.close_prepared(resource)
  def close(%Pending{resource: resource}), do: Native.close_pending(resource)

  @spec query(Connection.t(), iodata()) :: Result.t()
  def query(%Connection{} = connection, sql) do
    borrowed = query_borrowed(connection, sql)

    try do
      materialize(borrowed)
    after
      close(borrowed)
    end
  end

  @spec query_borrowed(Connection.t(), iodata()) :: BorrowedResult.t()
  def query_borrowed(%Connection{} = connection, sql) do
    %BorrowedResult{
      resource: Native.query(connection.resource, IO.iodata_to_binary(sql)),
      connection: connection
    }
  end

  @spec materialize(BorrowedResult.t()) :: Result.t()
  def materialize(%BorrowedResult{} = result) do
    column_count = Native.result_column_count(result.resource)
    row_count = Native.result_row_count(result.resource)

    columns =
      for column <- indices(column_count) do
        %{
          name: Native.result_column_name(result.resource, column),
          values:
            for row <- indices(row_count) do
              Native.result_value(result.resource, column, row)
            end
        }
      end

    %Result{
      columns: columns,
      row_count: row_count,
      rows_changed: Native.result_rows_changed(result.resource)
    }
  end

  @spec create_appender(Connection.t(), String.t()) :: Appender.t()
  def create_appender(%Connection{} = connection, table) when is_binary(table) do
    %Appender{
      resource: Native.create_appender(connection.resource, table),
      connection: connection
    }
  end

  @spec append(Appender.t(), [value()]) :: :ok
  def append(%Appender{} = appender, row) when is_list(row) do
    Native.append_row(appender.resource, Enum.map(row, &encode_appender_value/1))
  end

  @spec flush(Appender.t()) :: :ok
  def flush(%Appender{resource: resource}), do: Native.flush_appender(resource)

  @spec prepare(Connection.t(), iodata()) :: Prepared.t()
  def prepare(%Connection{} = connection, sql) do
    %Prepared{
      resource: Native.prepare(connection.resource, IO.iodata_to_binary(sql)),
      connection: connection
    }
  end

  @spec pending(Prepared.t(), [value()]) :: Pending.t()
  def pending(%Prepared{} = prepared, params \\ []) when is_list(params) do
    encoded = Enum.map(params, &encode_appender_value/1)
    %Pending{resource: Native.create_pending(prepared.resource, encoded), prepared: prepared}
  end

  @spec execute_pending(Pending.t()) :: BorrowedResult.t()
  def execute_pending(%Pending{} = pending) do
    run_pending(pending)

    %BorrowedResult{
      resource: Native.execute_pending(pending.resource),
      connection: pending.prepared.connection
    }
  end

  @spec interrupt(Connection.t()) :: :ok
  def interrupt(%Connection{resource: resource}), do: Native.interrupt(resource)

  @spec query_int64(iodata(), Path.t()) :: integer()
  def query_int64(sql, database \\ ":memory:") do
    Native.query_int64(IO.iodata_to_binary(database), IO.iodata_to_binary(sql))
  end

  defp encode_appender_value(nil), do: {:null}
  defp encode_appender_value(value) when is_boolean(value), do: {:boolean, value}
  defp encode_appender_value(value) when is_integer(value), do: {:integer, value}
  defp encode_appender_value(value) when is_float(value), do: {:float, value}
  defp encode_appender_value(value) when is_binary(value), do: {:string, value}

  defp run_pending(pending) do
    case Native.pending_task(pending.resource) do
      :ready -> :ok
      :not_ready -> run_pending(pending)
      :no_tasks -> run_pending(pending)
      :error -> raise Error, message: Native.pending_error(pending.resource), operation: :pending
    end
  end

  defp indices(0), do: []
  defp indices(count), do: 0..(count - 1)
end
