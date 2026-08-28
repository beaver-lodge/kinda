defmodule Kinda.Capsule.FailureMode do
  @moduledoc "Auditable score deduction tied to evidence."

  alias Kinda.Capsule.EvidenceRef

  @enforce_keys [:code, :message]
  defstruct [:code, :message, severity: :warning, evidence: [], metadata: %{}]

  @type t :: %__MODULE__{
          code: atom() | binary(),
          message: binary(),
          severity: :info | :warning | :critical,
          evidence: [EvidenceRef.t()],
          metadata: map()
        }

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = failure) do
    (is_atom(failure.code) or is_binary(failure.code)) and is_binary(failure.message) and
      failure.severity in [:info, :warning, :critical] and is_list(failure.evidence) and
      Enum.all?(failure.evidence, &EvidenceRef.valid?/1) and is_map(failure.metadata)
  end

  def valid?(_failure), do: false
end
