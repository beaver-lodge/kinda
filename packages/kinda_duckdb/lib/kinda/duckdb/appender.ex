defmodule Kinda.DuckDB.Appender do
  @moduledoc "A bulk Appender resource that retains its parent connection."

  alias Kinda.DuckDB.Connection

  @enforce_keys [:resource, :connection]
  defstruct [:resource, :connection]

  @opaque t :: %__MODULE__{resource: reference(), connection: Connection.t()}
end
