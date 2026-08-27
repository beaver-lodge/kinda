defmodule Kinda.Capsule.Action.Command do
  @moduledoc "The only action supported by the command-backed Capsule MVP."

  @enforce_keys [:spec]
  defstruct [:spec, metadata: %{}]

  @type t :: %__MODULE__{spec: Kinda.Sandbox.Command.Spec.t(), metadata: map()}
end
