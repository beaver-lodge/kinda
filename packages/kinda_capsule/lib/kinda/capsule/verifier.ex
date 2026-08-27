defmodule Kinda.Capsule.Verifier do
  @moduledoc "Synchronous, observation-only grading callback."

  alias Kinda.Capsule.{Score, Verification}

  @callback grade(Verification.t(), keyword()) :: {:ok, Score.t()} | {:error, term()}
end
