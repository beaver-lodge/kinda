defmodule Kinda.Sandbox.Handle do
  @moduledoc """
  Opaque, node-local reference to a sandbox.

  Backend state, owner identity, and capabilities deliberately stay inside the
  sandbox runtime rather than being copied into this value.
  """

  @enforce_keys [:ref]
  defstruct [:ref]

  @opaque t :: %__MODULE__{ref: reference()}

  @doc false
  @spec new(reference()) :: t()
  def new(ref) when is_reference(ref), do: %__MODULE__{ref: ref}
end
