defmodule Kinda.DuckDB.Query do
  @moduledoc "A DBConnection query backed by an optional DuckDB prepared statement."

  alias Kinda.DuckDB.Prepared

  @enforce_keys [:statement]
  defstruct [:statement, :name, :prepared]

  @type t :: %__MODULE__{
          statement: String.t(),
          name: String.t() | nil,
          prepared: Prepared.t() | nil
        }
end

defimpl DBConnection.Query, for: Kinda.DuckDB.Query do
  def parse(query, _options), do: query
  def describe(query, _options), do: query
  def encode(_query, params, _options) when is_list(params), do: params
  def decode(_query, result, _options), do: result
end

defimpl String.Chars, for: Kinda.DuckDB.Query do
  def to_string(query), do: query.statement
end
