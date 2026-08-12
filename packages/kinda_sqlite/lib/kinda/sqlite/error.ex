defmodule Kinda.SQLite.Error do
  @moduledoc "Structured SQLite driver error."

  defexception [:message, :code, :extended_code, :operation, :sql, :call_error]

  @type t :: %__MODULE__{
          message: String.t(),
          code: integer() | atom() | nil,
          extended_code: integer() | nil,
          operation: atom() | nil,
          sql: String.t() | nil,
          call_error: Exception.t() | nil
        }

  @doc false
  def from_call(call_error, operation, sql \\ nil)

  def from_call(%{message: message} = call_error, operation, sql) do
    %__MODULE__{message: message, operation: operation, sql: sql, call_error: call_error}
  end

  def from_call(nil, operation, sql) do
    %__MODULE__{message: "SQLite #{operation} failed", operation: operation, sql: sql}
  end
end
