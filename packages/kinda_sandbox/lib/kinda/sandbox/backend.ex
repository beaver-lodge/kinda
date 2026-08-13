defmodule Kinda.Sandbox.Backend do
  @moduledoc """
  Minimal lifecycle contract implemented by sandbox backends.

  Backend handles never cross the public API boundary. Capability modules
  receive them only after the owning sandbox process has serialized access.
  """

  alias Kinda.Sandbox.Error

  @type backend_handle :: term()
  @type capability :: atom()
  @type capability_module :: module()

  @callback capabilities() :: %{optional(capability()) => capability_module()}
  @callback create(spec :: term(), options :: keyword()) ::
              {:ok, backend_handle()} | {:error, Error.t()}
  @callback close(backend_handle()) :: :ok | {:error, Error.t()}
end
