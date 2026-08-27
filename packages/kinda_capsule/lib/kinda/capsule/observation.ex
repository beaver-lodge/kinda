defmodule Kinda.Capsule.Observation do
  @moduledoc "Task-defined observation returned to an episode caller."

  @enforce_keys [:value]
  defstruct [:value, metadata: %{}]

  @type t :: %__MODULE__{value: term(), metadata: map()}
end
