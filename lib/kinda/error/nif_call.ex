defmodule Kinda.CallError do
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
