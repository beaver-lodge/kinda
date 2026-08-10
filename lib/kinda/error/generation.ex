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
    [
      error.message || "code generation failed",
      format_field("stage", error.stage),
      format_field("reason", error.reason),
      format_field("source", error.source),
      format_field("expected", error.expected),
      format_field("actual", error.actual)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_field(_name, nil), do: nil
  defp format_field(name, value), do: "#{name}: #{inspect(value, pretty: true)}"
end
