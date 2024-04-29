defmodule Kinda.CallError do
  defexception [:message, :error_return_trace]

  @impl true
  def message(t) do
    """
    #{t.message}
    #{t.error_return_trace}
    """
  end
end
