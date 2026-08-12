defmodule Kinda.SQLite.Database do
  @moduledoc "An open SQLite database resource."

  @enforce_keys [:resource, :path]
  defstruct [:resource, :path]

  @opaque t :: %__MODULE__{resource: reference(), path: String.t()}
end
