defmodule Kinda.CommandError do
  @moduledoc """
  The exception raised when an external command cannot be run successfully.

  In addition to its human-readable message, the exception retains the exact
  command, arguments, working directory, exit status and captured output so
  callers can inspect failures without parsing text.
  """

  @type t() :: %__MODULE__{
          message: String.t() | nil,
          stage: atom() | nil,
          command: String.t() | nil,
          args: [String.t()],
          cwd: Path.t() | nil,
          status: non_neg_integer() | nil,
          output: String.t() | nil,
          reason: term()
        }

  defexception message: nil,
               stage: nil,
               command: nil,
               args: [],
               cwd: nil,
               status: nil,
               output: nil,
               reason: nil

  @impl true
  def message(%__MODULE__{} = error) do
    [
      error.message || "external command failed",
      format_stage(error.stage),
      format_command(error.command, error.args),
      format_field("cwd", error.cwd),
      format_field("status", error.status),
      format_field("reason", error.reason),
      format_output(error.output)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_stage(nil), do: nil
  defp format_stage(stage), do: "stage: #{stage}"

  defp format_command(nil, _args), do: nil

  defp format_command(command, args),
    do: "command: " <> Enum.join([command | args], " ")

  defp format_field(_name, nil), do: nil
  defp format_field(name, value), do: "#{name}: #{inspect(value)}"

  defp format_output(nil), do: nil
  defp format_output(""), do: nil
  defp format_output(output), do: "\n" <> String.trim_trailing(output)
end
