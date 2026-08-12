defmodule Kinda.DuckDB.Prepared do
  @moduledoc "A prepared DuckDB statement that retains its parent connection."

  alias Kinda.DuckDB.Connection

  @enforce_keys [:resource, :connection]
  defstruct [:resource, :connection]

  @opaque t :: %__MODULE__{resource: reference(), connection: Connection.t()}
end
