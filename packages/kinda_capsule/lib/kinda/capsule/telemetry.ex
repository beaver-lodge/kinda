defmodule Kinda.Capsule.Telemetry do
  @moduledoc false

  @prefix [:kinda, :capsule]

  def emit(operation, duration, metadata) do
    :telemetry.execute(@prefix ++ [operation], %{duration: duration}, metadata)
  end
end
