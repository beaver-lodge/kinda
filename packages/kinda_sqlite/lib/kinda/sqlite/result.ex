defmodule Kinda.SQLite.Result do
  @moduledoc "Result returned by a SQLite query or statement execution."

  @enforce_keys [:columns, :rows, :num_rows]
  defstruct [:columns, :rows, :num_rows]

  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[term()]],
          num_rows: non_neg_integer()
        }
end
