defmodule Kinda.NIFLoadError do
  @moduledoc """
  The exception raised when the BEAM cannot load a generated native library.

  The attempted path and the original `:erlang.load_nif/2` reason remain
  available as structured fields.
  """

  @type t() :: %__MODULE__{
          message: String.t() | nil,
          path: Path.t() | charlist() | nil,
          reason: term()
        }

  defexception [:message, :path, :reason]

  @impl true
  def message(%__MODULE__{} = error) do
    [
      error.message || "NIF load failed",
      format_field("path", error.path),
      format_field("reason", error.reason)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_field(_name, nil), do: nil
  defp format_field(name, value), do: "#{name}: #{inspect(value)}"
end
