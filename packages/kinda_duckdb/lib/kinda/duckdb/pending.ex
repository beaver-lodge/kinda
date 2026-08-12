defmodule Kinda.DuckDB.Pending do
  @moduledoc "An incrementally executed DuckDB pending query."

  alias Kinda.DuckDB.Prepared

  @enforce_keys [:resource, :prepared]
  defstruct [:resource, :prepared]

  @opaque t :: %__MODULE__{resource: reference(), prepared: Prepared.t()}
end
