defmodule Kinda.SQLite.Query do
  @moduledoc "A DBConnection query backed by an optional prepared SQLite statement."

  alias Kinda.SQLite.Statement

  @enforce_keys [:statement]
  defstruct [:statement, :name, :prepared]

  @type t :: %__MODULE__{
          statement: String.t(),
          name: String.t() | nil,
          prepared: Statement.t() | nil
        }
end

defimpl DBConnection.Query, for: Kinda.SQLite.Query do
  def parse(query, _opts), do: query
  def describe(query, _opts), do: query
  def encode(_query, params, _opts) when is_list(params), do: params
  def decode(_query, result, _opts), do: result
end
