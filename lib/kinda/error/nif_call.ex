defmodule Kinda.CallError do
  @moduledoc """
  The exception raised when a generated NIF call fails.

  The message includes the error returned by the NIF and a hint to enable
  `KINDA_DUMP_STACK_TRACE=1` for the full native stack trace.
  """

  defexception [:message]

  @impl true
  def message(t) do
    notice = "to see the full stack trace, set KINDA_DUMP_STACK_TRACE=1"

    """
    #{t.message}
    #{notice}
    """
  end
end
