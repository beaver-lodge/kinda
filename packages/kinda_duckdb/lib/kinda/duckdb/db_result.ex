defmodule Kinda.DuckDB.DBResult do
  @moduledoc "Row-oriented result returned through DBConnection."

  @enforce_keys [:columns, :rows, :num_rows]
  defstruct [:columns, :rows, :num_rows]

  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[Kinda.DuckDB.value()]] | nil,
          num_rows: non_neg_integer()
        }
end
