defmodule Kinda.Capsule.Verification do
  @moduledoc "Read-only value passed to a Capsule verifier."

  alias Kinda.Capsule.{Episode, Observation, Trace}

  @enforce_keys [
    :capsule_id,
    :episode_id,
    :task_version,
    :verifier_version,
    :seed,
    :observation,
    :trace,
    :episode
  ]
  defstruct [
    :capsule_id,
    :episode_id,
    :task_version,
    :verifier_version,
    :seed,
    :observation,
    :trace,
    :episode
  ]

  @type t :: %__MODULE__{
          capsule_id: binary(),
          episode_id: binary(),
          task_version: binary(),
          verifier_version: binary(),
          seed: term(),
          observation: Observation.t(),
          trace: Trace.t(),
          episode: Episode.t()
        }
end
