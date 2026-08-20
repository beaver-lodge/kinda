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
              {:ok, Enumerable.t()}
              | {:ok, Enumerable.t(), backend_execution :: term()}
              | {:error, Error.t()}

  @callback terminate(
              backend_execution :: term(),
              reason :: :cancelled | :timeout | :sandbox_closed,
              grace_milliseconds :: non_neg_integer()
            ) :: :ok

  @optional_callbacks terminate: 3
end
