defmodule Kinda.Capsule.Task do
  @moduledoc "Trusted task callbacks for reset, observation, and cleanup."

  alias Kinda.Capsule.{Context, Observation}

  @callback reset(Context.t(), seed :: term(), keyword()) ::
              {:ok, task_state :: term(), Observation.t()} | {:error, term()}
  @callback observe(Context.t(), task_state :: term()) ::
              {:ok, Observation.t()} | {:error, term()}
  @callback close(Context.t(), task_state :: term()) :: :ok | {:error, term()}
end
