defmodule Kinda.DuckDB.Result do
  @moduledoc "A safe BEAM-owned columnar DuckDB result."

  @enforce_keys [:columns, :row_count, :rows_changed]
  defstruct [:columns, :row_count, :rows_changed]

  @type column :: %{name: String.t(), values: [Kinda.DuckDB.value()]}
  @type t :: %__MODULE__{
          columns: [column()],
          row_count: non_neg_integer(),
          rows_changed: non_neg_integer()
        }
end
