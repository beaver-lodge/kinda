defmodule Kinda.Capsule.Context do
  @moduledoc "Context supplied to trusted Task callbacks."

  @enforce_keys [:capsule_id, :sandbox, :seed]
  defstruct [:capsule_id, :sandbox, :seed]

  @type t :: %__MODULE__{
          capsule_id: binary(),
          sandbox: Kinda.Sandbox.Handle.t(),
          seed: term()
        }
end
