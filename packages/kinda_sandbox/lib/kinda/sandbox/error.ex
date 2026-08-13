defmodule Kinda.Sandbox.Error do
  @moduledoc "A normalized error returned by sandbox facades and backends."

  @enforce_keys [:reason]
  defexception [:reason, :message, :backend, :operation, :cause, :details]

  @type reason ::
          :invalid_spec
          | :unsupported_capability
          | :disconnected
          | :backend_failure

  @type t :: %__MODULE__{
          reason: reason(),
          message: binary() | nil,
          backend: module() | nil,
          operation: atom() | nil,
          cause: term(),
          details: term()
        }

  @impl Exception
  def exception(options) do
    reason = Keyword.fetch!(options, :reason)
    message = Keyword.get(options, :message, default_message(reason))
    backend = Keyword.get(options, :backend)
    operation = Keyword.get(options, :operation)
    cause = Keyword.get(options, :cause)
    details = Keyword.get(options, :details)

    %__MODULE__{
      reason: reason,
      message: message,
      backend: backend,
      operation: operation,
      cause: cause,
      details: details
    }
  end

  defp default_message(:invalid_spec), do: "invalid sandbox specification"
  defp default_message(:unsupported_capability), do: "sandbox capability is not supported"
  defp default_message(:disconnected), do: "sandbox is disconnected"
  defp default_message(:backend_failure), do: "sandbox backend failed"
end
