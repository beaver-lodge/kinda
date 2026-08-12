defmodule Kinda.DuckDB.Cursor do
  @moduledoc false

  @enforce_keys [:columns, :ref]
  defstruct [:columns, :ref]

  @type t :: %__MODULE__{columns: [String.t()], ref: reference()}
end
