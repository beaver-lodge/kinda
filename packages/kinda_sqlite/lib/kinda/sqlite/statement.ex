defmodule Kinda.SQLite.Statement do
  @moduledoc "A prepared SQLite statement that retains its database."

  alias Kinda.SQLite.Database

  @enforce_keys [:resource, :database, :sql]
  defstruct [:resource, :database, :sql]

  @opaque t :: %__MODULE__{resource: reference(), database: Database.t(), sql: String.t()}
end
