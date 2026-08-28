defmodule Kinda.Capsule.Score do
  @moduledoc "Validated result of synchronous Capsule grading."

  alias Kinda.Capsule.{FailureMode, ScoreComponent}

  @enforce_keys [:value]
  defstruct [:value, components: %{}, gates: %{}, failure_modes: [], metadata: %{}]

  @type t :: %__MODULE__{
          value: number(),
          components: %{
            optional(atom() | binary()) => number() | ScoreComponent.t()
          },
          gates: %{optional(atom() | binary()) => :pass | :fail},
          failure_modes: [FailureMode.t()],
          metadata: map()
        }

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = score) do
    is_number(score.value) and is_map(score.components) and is_map(score.gates) and
      valid_gates?(score.gates) and is_list(score.failure_modes) and
      valid_failure_modes?(score.failure_modes) and is_map(score.metadata) and
      valid_components?(score.components)
  end

  def valid?(_score), do: false

  defp valid_gates?(gates) do
    Enum.all?(gates, fn {key, result} ->
      (is_atom(key) or is_binary(key)) and result in [:pass, :fail]
    end)
  end

  defp valid_failure_modes?(failure_modes) do
    Enum.all?(failure_modes, &FailureMode.valid?/1)
  end

  defp valid_components?(components) do
    Enum.all?(components, fn {key, component} ->
      (is_atom(key) or is_binary(key)) and
        (is_number(component) or ScoreComponent.valid?(component))
    end)
  end
end
