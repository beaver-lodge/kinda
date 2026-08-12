defmodule Ecto.Adapters.KindaDuckDB do
  @moduledoc """
  Experimental Ecto SQL adapter backed by Kinda DuckDB.

  The supported surface is deliberately analytical: SQL queries, Ecto read
  queries, streams, and top-level transactions. Schema writes, migrations,
  nested transactions, constraint translation, and PostgreSQL OLTP semantics
  are not promised.

  Ecto's maintained PostgreSQL query generator supplies the read-query dialect,
  while all database I/O and native resource ownership use Kinda DuckDB.
  """

  use Ecto.Adapters.SQL, driver: :kinda_duckdb

  @behaviour Ecto.Adapter.Storage

  alias Ecto.Adapters.Postgres, as: PostgresDialect

  @impl Ecto.Adapter.Storage
  def storage_up(options) do
    database = database!(options)

    if database != ":memory:" and File.exists?(database) do
      {:error, :already_up}
    else
      database |> Kinda.DuckDB.open() |> Kinda.DuckDB.close()
      :ok
    end
  rescue
    error -> {:error, error}
  end

  @impl Ecto.Adapter.Storage
  def storage_down(options) do
    case database!(options) do
      ":memory:" -> {:error, :already_down}
      database -> remove_database(database)
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_status(options) do
    database = database!(options)
    if database != ":memory:" and File.exists?(database), do: :up, else: :down
  end

  @impl Ecto.Adapter.Migration
  def supports_ddl_transaction?, do: false

  @impl Ecto.Adapter.Migration
  def lock_for_migrations(_meta, _options, _function) do
    raise ArgumentError, "Ecto migrations are not supported by the experimental DuckDB adapter"
  end

  @impl Ecto.Adapter
  defdelegate loaders(primitive, type), to: PostgresDialect

  @impl Ecto.Adapter
  defdelegate dumpers(primitive, type), to: PostgresDialect

  @impl Ecto.Adapter.Schema
  defdelegate autogenerate(type), to: PostgresDialect

  @impl Ecto.Adapter.Schema
  def insert(_adapter_meta, _schema_meta, _params, _on_conflict, _returning, _options) do
    unsupported!(:insert)
  end

  @impl Ecto.Adapter.Schema
  def update(_adapter_meta, _schema_meta, _fields, _params, _returning, _options) do
    unsupported!(:update)
  end

  @impl Ecto.Adapter.Schema
  def delete(_adapter_meta, _schema_meta, _params, _returning, _options) do
    unsupported!(:delete)
  end

  @impl Ecto.Adapter.Schema
  def insert_all(
        _adapter_meta,
        _schema_meta,
        _header,
        _rows,
        _on_conflict,
        _returning,
        _placeholders,
        _options
      ) do
    unsupported!(:insert_all)
  end

  @impl Ecto.Adapter.Migration
  def execute_ddl(_adapter_meta, _definition, _options), do: unsupported!(:migration)

  defp database!(options) do
    case Keyword.fetch(options, :database) do
      {:ok, :memory} -> ":memory:"
      {:ok, database} when is_binary(database) -> database
      _ -> raise ArgumentError, "expected :database to be a DuckDB path or :memory"
    end
  end

  defp remove_database(database) do
    case File.rm(database) do
      :ok -> :ok
      {:error, :enoent} -> {:error, :already_down}
      {:error, reason} -> {:error, reason}
    end
  end

  defp unsupported!(operation) do
    raise Kinda.DuckDB.Error,
      message: "#{operation} is not supported by the experimental DuckDB Ecto adapter",
      operation: operation
  end
end
