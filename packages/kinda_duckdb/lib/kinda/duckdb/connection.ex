defmodule Kinda.DuckDB.Connection do
  @moduledoc "A DuckDB connection that retains its parent database."

  alias Kinda.DuckDB.Database

  @enforce_keys [:resource, :database]
  defstruct [:resource, :database]

  @opaque t :: %__MODULE__{resource: reference(), database: Database.t()}
end
