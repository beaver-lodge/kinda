defmodule Kinda.SQLite.Cursor do
  @moduledoc false

  @enforce_keys [:columns, :statement]
  defstruct [:columns, :statement]
end
