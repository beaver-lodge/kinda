defmodule Kinda.Capsule.Episode do
  @moduledoc "Stable identity and comparison metadata for one reset attempt."

  alias Kinda.Capsule.RuntimeFingerprint

  @enforce_keys [
    :capsule_id,
    :episode_id,
    :capsule_version,
    :task_version,
    :fixture_digest,
    :verifier_version,
    :verifier_digest,
    :runtime
  ]
  defstruct [
    :capsule_id,
    :episode_id,
    :capsule_version,
    :task_version,
    :fixture_digest,
    :verifier_version,
    :verifier_digest,
    :runtime,
    model: %{}
  ]

  @type t :: %__MODULE__{
          capsule_id: binary(),
          episode_id: binary(),
          capsule_version: binary(),
          task_version: binary(),
          fixture_digest: binary(),
          verifier_version: binary(),
          verifier_digest: binary(),
          runtime: RuntimeFingerprint.t(),
          model: map()
        }
end
