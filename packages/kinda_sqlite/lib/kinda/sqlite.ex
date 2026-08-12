defmodule Kinda.SQLite do
  @moduledoc """
  Low-level SQLite driver primitives backed by a Kinda NIF.

  This package deliberately owns the native SQLite boundary but not Ecto's
  repository or query-planning concerns. A DBConnection implementation can
  build on these primitives without exposing NIF modules to its callers.
  """

  alias Kinda.SQLite.Native

  defdelegate open_memory(), to: Native
  defdelegate execute(database, sql), to: Native
  defdelegate prepare(database, sql), to: Native
  defdelegate bind_int64(statement, index, value), to: Native
  defdelegate bind_text(statement, index, value), to: Native
  defdelegate step(statement), to: Native
  defdelegate column_int64(statement, index), to: Native
  defdelegate column_text(statement, index), to: Native
  defdelegate database_changes(database), to: Native
  defdelegate sqlite_version(), to: Native
end
