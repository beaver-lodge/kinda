defmodule Kinda.Sandbox.Capability.NativeBuild do
  @moduledoc "Contract implemented by backend-specific native build capabilities."

  alias Kinda.Sandbox.Error

  @type builder_mfa :: {module(), atom(), [term()]}

  @callback build(backend_handle :: term(), builder_mfa()) ::
              {:ok, artifact :: binary()} | {:error, Error.t()}
end
