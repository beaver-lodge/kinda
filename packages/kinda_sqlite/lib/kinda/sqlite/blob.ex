defmodule Kinda.SQLite.Blob do
  @moduledoc "Explicit wrapper distinguishing SQLite BLOB parameters and values from TEXT."

  @enforce_keys [:data]
  defstruct [:data]

  @type t :: %__MODULE__{data: binary()}
end
