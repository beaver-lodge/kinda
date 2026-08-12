defmodule Ecto.Adapters.KindaSQLite do
  @moduledoc """
  Ecto SQL adapter backed by `Kinda.SQLite.Connection`.

  The adapter uses SQLite semantics and SQL generation while keeping the
  connection, prepared statement, streaming, and resource lifecycle path in
  Kinda SQLite.
  """

  use Ecto.Adapters.SQL, driver: :kinda_sqlite

  @behaviour Ecto.Adapter.Storage

  alias Ecto.Adapters.SQLite3, as: SQLiteDialect
  alias Kinda.SQLite.Blob

  @impl Ecto.Adapter.Storage
  def storage_up(options) do
    database = database!(options)
    validate_pool!(database, Keyword.get(options, :pool_size, 1))

    if database != ":memory:" and File.exists?(database) do
      {:error, :already_up}
    else
      case Kinda.SQLite.open(database) do
        {:ok, connection} ->
          Kinda.SQLite.close(connection)
          :ok

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_down(options) do
    database = database!(options)

    if database == ":memory:" do
      {:error, :already_down}
    else
      case File.rm(database) do
        :ok ->
          remove_sidecar(database <> "-shm")
          remove_sidecar(database <> "-wal")
          :ok

        {:error, :enoent} ->
          {:error, :already_down}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_status(options) do
    database = database!(options)

    if database != ":memory:" and File.exists?(database), do: :up, else: :down
  end

  @impl Ecto.Adapter.Migration
  def supports_ddl_transaction?, do: true

  @impl Ecto.Adapter.Migration
  def lock_for_migrations(_meta, _options, function), do: function.()

  @impl Ecto.Adapter
  def loaders(:binary, type), do: [&blob_decode/1, type]
  def loaders(primitive, type), do: SQLiteDialect.loaders(primitive, type)

  @impl Ecto.Adapter
  def dumpers(:binary, type), do: [type, &blob_encode/1]
  def dumpers(primitive, type), do: SQLiteDialect.dumpers(primitive, type)

  @impl Ecto.Adapter.Schema
  def autogenerate(type), do: SQLiteDialect.autogenerate(type)

  defp blob_decode(%Blob{data: data}), do: {:ok, data}
  defp blob_decode(data), do: {:ok, data}

  defp blob_encode(nil), do: {:ok, nil}
  defp blob_encode(data) when is_binary(data), do: {:ok, %Blob{data: data}}
  defp blob_encode(_data), do: :error

  defp database!(options) do
    case Keyword.fetch(options, :database) do
      {:ok, :memory} -> ":memory:"
      {:ok, database} when is_binary(database) -> database
      _ -> raise ArgumentError, "expected :database to be a SQLite path or :memory"
    end
  end

  defp validate_pool!(":memory:", pool_size) when pool_size != 1 do
    raise ArgumentError, "in-memory SQLite databases require pool_size: 1"
  end

  defp validate_pool!(_database, _pool_size), do: :ok

  defp remove_sidecar(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _reason} -> :ok
    end
  end
end
