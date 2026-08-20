defmodule Kinda.Sandbox.Capability.Command do
  @moduledoc "Backend capability contract for structured command execution."

  alias Kinda.Sandbox.Command.Spec
  alias Kinda.Sandbox.Error

  @type event ::
          {:stdout, iodata()}
          | {:stderr, iodata()}
          | {:exit, non_neg_integer()}
          | {:signal, non_neg_integer()}
          | {:metadata, map()}

  @callback stream(backend_handle :: term(), Spec.t()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}

  @callback terminate(worker :: pid(), reason :: :cancelled | :timeout | :sandbox_closed) :: :ok

  @optional_callbacks terminate: 2
end
