defmodule Kinda.Capsule.Step do
  @moduledoc "Safe terminal projection of one accepted Capsule action."

  alias Kinda.Capsule.CommandSummary

  @enforce_keys [
    :sequence,
    :action,
    :termination,
    :stdout,
    :stderr,
    :duration,
    :stdout_truncated?,
    :stderr_truncated?
  ]
  defstruct [
    :sequence,
    :action,
    :termination,
    :stdout,
    :stderr,
    :duration,
    :stdout_truncated?,
    :stderr_truncated?,
    evidence: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          sequence: non_neg_integer(),
          action: CommandSummary.t(),
          termination: Kinda.Sandbox.Command.Result.termination(),
          stdout: binary(),
          stderr: binary(),
          duration: non_neg_integer(),
          stdout_truncated?: boolean(),
          stderr_truncated?: boolean(),
          evidence: [Kinda.Capsule.EvidenceRef.t()],
          metadata: map()
        }
end
