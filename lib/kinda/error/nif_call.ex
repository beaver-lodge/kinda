defmodule Kinda.CallError do
  defexception [:message, :error_return_trace]

  @impl true
  def message(t) do
    notice = "to see the full stack trace, set KINDA_DUMP_STACK_TRACE=1"

    """
    #{t.message}
    #{t.error_return_trace || notice}
    """
  end
end
