defmodule Kinda.GenerationError do
  @moduledoc """
  The exception raised when Kinda cannot resolve or generate a declaration.

  `:stage` and `:reason` are stable identifiers. `:source`, `:expected` and
  `:actual` retain the values needed to diagnose malformed generator input.
  """

  @type t() :: %__MODULE__{
          message: String.t() | nil,
          stage: atom() | nil,
          reason: atom() | nil,
          source: term(),
          expected: term(),
          actual: term()
        }

  defexception [:message, :stage, :reason, :source, :expected, :actual]

  @impl true
  def message(%__MODULE__{} = error) do
    details =
      for key <- ~w(stage reason source expected actual)a,
          value = Map.fetch!(error, key),
          value != nil,
          do: "#{key}: #{inspect(value, pretty: true)}"

    Enum.join([error.message || "code generation failed" | details], "\n")
  end
end
