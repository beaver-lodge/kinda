defmodule Kinda.Capsule.Trace do
  @moduledoc "Ordered, in-memory trace for the current episode."

  alias Kinda.Capsule.{Score, Step}

  @enforce_keys [:capsule_id, :task_version, :verifier_version, :seed]
  defstruct [:capsule_id, :task_version, :verifier_version, :seed, steps: [], score: nil]

  @type t :: %__MODULE__{
          capsule_id: binary(),
          task_version: binary(),
          verifier_version: binary(),
          seed: term(),
          steps: [Step.t()],
          score: Score.t() | nil
        }
end
