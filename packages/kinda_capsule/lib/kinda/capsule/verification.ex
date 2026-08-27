defmodule Kinda.Capsule.Verification do
  @moduledoc "Read-only value passed to a Capsule verifier."

  alias Kinda.Capsule.{Observation, Trace}

  @enforce_keys [
    :capsule_id,
    :task_version,
    :verifier_version,
    :seed,
    :observation,
    :trace
  ]
  defstruct [:capsule_id, :task_version, :verifier_version, :seed, :observation, :trace]

  @type t :: %__MODULE__{
          capsule_id: binary(),
          task_version: binary(),
          verifier_version: binary(),
          seed: term(),
          observation: Observation.t(),
          trace: Trace.t()
        }
end
