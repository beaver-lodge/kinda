defmodule Kinda.Capsule.Trace do
  @moduledoc "Ordered, in-memory trace for the current episode."

  alias Kinda.Capsule.{Artifact, Episode, Score, Step}

  @enforce_keys [:capsule_id, :episode_id, :task_version, :verifier_version, :seed, :episode]
  defstruct [
    :capsule_id,
    :episode_id,
    :task_version,
    :verifier_version,
    :seed,
    :episode,
    steps: [],
    artifacts: [],
    score: nil
  ]

  @type t :: %__MODULE__{
          capsule_id: binary(),
          episode_id: binary(),
          task_version: binary(),
          verifier_version: binary(),
          seed: term(),
          episode: Episode.t(),
          steps: [Step.t()],
          artifacts: [Artifact.t()],
          score: Score.t() | nil
        }
end
