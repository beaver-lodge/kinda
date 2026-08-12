defmodule Kinda.DuckDB.BorrowedResult do
  @moduledoc "A native result that retains the connection whose buffers it borrows."

  alias Kinda.DuckDB.Connection

  @enforce_keys [:resource, :connection]
  defstruct [:resource, :connection]

  @opaque t :: %__MODULE__{resource: reference(), connection: Connection.t()}
end
