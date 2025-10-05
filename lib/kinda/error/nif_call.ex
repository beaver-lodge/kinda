defmodule Kinda.CallError do
  defexception [:message, :error_return_trace]

  @impl true
  def message(%{message: msg, error_return_trace: nil}), do: msg

  def message(%{message: msg, error_return_trace: trace}) do
    "#{msg}\n#{IO.ANSI.reset()}#{trace}"
  end
end
