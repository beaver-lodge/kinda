defmodule Kinda.Capsule.SealedVerifier do
  @moduledoc "Verifier contract for immutable exported evidence."

  alias Kinda.Capsule.Score

  @callback version() :: binary()
  @callback digest() :: binary()
  @callback regrade(bundle :: map(), keyword()) :: {:ok, Score.t()} | {:error, term()}
end
