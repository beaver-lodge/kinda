defmodule KindaSqliteExample do
  @moduledoc "A real-world SQLite integration example for Kinda."

  alias KindaSqliteExample.NIF.Raw

  defdelegate open_memory(), to: Raw
  defdelegate execute(database, sql), to: Raw
  defdelegate prepare(database, sql), to: Raw
  defdelegate bind_int64(statement, index, value), to: Raw
  defdelegate bind_text(statement, index, value), to: Raw
  defdelegate step(statement), to: Raw
  defdelegate column_int64(statement, index), to: Raw
  defdelegate column_text(statement, index), to: Raw
  defdelegate database_changes(database), to: Raw
  defdelegate sqlite_version(), to: Raw
end
