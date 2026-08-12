defmodule Kinda.DuckDB.Error do
  @moduledoc "Structured DuckDB driver error."

  defexception [:message, :operation, :sql, :call_error]

  @type t :: %__MODULE__{
          message: String.t(),
          operation: atom() | nil,
          sql: String.t() | nil,
          call_error: Exception.t() | nil
        }
end
