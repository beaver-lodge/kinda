defmodule Kinda.Capsule.Score do
  @moduledoc "Validated result of synchronous Capsule grading."

  @enforce_keys [:value]
  defstruct [:value, components: %{}, metadata: %{}]

  @type t :: %__MODULE__{
          value: number(),
          components: %{optional(atom() | binary()) => number()},
          metadata: map()
        }

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{value: value, components: components, metadata: metadata}) do
    is_number(value) and is_map(components) and is_map(metadata) and
      Enum.all?(components, fn {key, component} ->
        (is_atom(key) or is_binary(key)) and is_number(component)
      end)
  end

  def valid?(_score), do: false
end
