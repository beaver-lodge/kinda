defmodule Kinda.Capsule.EvidenceRef do
  @moduledoc "Stable reference from a judgment or event to sealed evidence."

  @enforce_keys [:artifact]
  defstruct [:artifact, :fragment, metadata: %{}]

  @type t :: %__MODULE__{artifact: binary(), fragment: binary() | nil, metadata: map()}

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{artifact: artifact, fragment: fragment, metadata: metadata}) do
    is_binary(artifact) and artifact != "" and
      (is_nil(fragment) or is_binary(fragment)) and is_map(metadata)
  end

  def valid?(_reference), do: false
end
