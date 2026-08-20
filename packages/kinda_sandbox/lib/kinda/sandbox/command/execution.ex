defmodule Kinda.Sandbox.Command.Execution do
  @moduledoc "Opaque, node-local handle for a running or completed command."

  @enforce_keys [:ref]
  defstruct [:ref]

  @opaque t :: %__MODULE__{ref: reference()}

  @doc false
  def new(ref) when is_reference(ref), do: %__MODULE__{ref: ref}
end
