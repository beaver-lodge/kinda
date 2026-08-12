defmodule Kinda.DuckDB.Database do
  @moduledoc "An open DuckDB database resource."

  @enforce_keys [:resource, :path]
  defstruct [:resource, :path]

  @opaque t :: %__MODULE__{resource: reference(), path: String.t()}
end
