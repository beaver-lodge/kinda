defmodule Kinda.Capsule.RuntimeFingerprint do
  @moduledoc "Comparable runtime facts attached to one episode."

  defstruct browser: nil,
            os: nil,
            gpu: nil,
            driver: nil,
            device_pixel_ratio: nil,
            viewport: nil,
            fonts: [],
            cache_policy: nil,
            metadata: %{}

  @type t :: %__MODULE__{
          browser: binary() | nil,
          os: binary() | nil,
          gpu: binary() | nil,
          driver: binary() | nil,
          device_pixel_ratio: number() | nil,
          viewport: %{optional(:width | :height) => pos_integer()} | nil,
          fonts: [binary()],
          cache_policy: binary() | nil,
          metadata: map()
        }

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = fingerprint) do
    valid_strings?(fingerprint) and optional_number?(fingerprint.device_pixel_ratio) and
      valid_viewport?(fingerprint.viewport) and valid_fonts?(fingerprint.fonts) and
      is_map(fingerprint.metadata)
  end

  def valid?(_fingerprint), do: false

  defp valid_strings?(fingerprint) do
    Enum.all?(
      [
        fingerprint.browser,
        fingerprint.os,
        fingerprint.gpu,
        fingerprint.driver,
        fingerprint.cache_policy
      ],
      &optional_string?/1
    )
  end

  defp valid_fonts?(fonts), do: is_list(fonts) and Enum.all?(fonts, &is_binary/1)

  defp optional_string?(nil), do: true
  defp optional_string?(value), do: is_binary(value)
  defp optional_number?(nil), do: true
  defp optional_number?(value), do: is_number(value) and value > 0
  defp valid_viewport?(nil), do: true

  defp valid_viewport?(%{width: width, height: height}),
    do: is_integer(width) and width > 0 and is_integer(height) and height > 0

  defp valid_viewport?(_viewport), do: false
end
