defmodule Kinda.Capsule.ScoreComponent do
  @moduledoc "One scored dimension with its supporting evidence."

  alias Kinda.Capsule.EvidenceRef

  @enforce_keys [:value]
  defstruct [:value, evidence: [], metadata: %{}]

  @type t :: %__MODULE__{value: number(), evidence: [EvidenceRef.t()], metadata: map()}

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{value: value, evidence: evidence, metadata: metadata}) do
    is_number(value) and is_list(evidence) and Enum.all?(evidence, &EvidenceRef.valid?/1) and
      is_map(metadata)
  end

  def valid?(_component), do: false
end
