defmodule Kinda.CallbackRuntime do
  @moduledoc """
  Executes the BEAM side of a native callback and completes its reply token.

  The native consumer supplies its own two-argument reply NIF. Callback
  functions return `{:ok, value}` or `{:error, value}` so domain adapters can
  retain their own state and diagnostics semantics while Kinda owns the common
  success/failure and exception boundary.
  """

  @type callback_result(value) :: {:ok, value} | {:error, value}
  @type outcome(value) ::
          callback_result(value)
          | {:exception, :error | :exit | :throw, term(), Exception.stacktrace()}

  @doc """
  Executes a callback and gives the complete normalized outcome to a
  consumer-defined reply function.

  This is the projection boundary for callback ABIs whose return is richer
  than success/failure. A consumer may encode a scalar or enum result, or
  validate a resource and project its native handle, before completing the
  reply token.
  """
  @spec invoke_reply(
          reply_token :: term(),
          callback :: (-> callback_result(value)),
          reply :: (term(), outcome(value) -> term()),
          before_reply :: (outcome(value) -> term())
        ) :: outcome(value)
        when value: term()
  def invoke_reply(reply_token, callback, reply, before_reply \\ fn _outcome -> :ok end)
      when is_function(callback, 0) and is_function(reply, 2) and
             is_function(before_reply, 1) do
    outcome = callback |> capture() |> observe(before_reply)
    reply.(reply_token, outcome)
    outcome
  end

  @spec invoke(
          reply_token :: term(),
          callback :: (-> callback_result(value)),
          reply :: (term(), boolean() -> term()),
          before_reply :: (outcome(value) -> term())
        ) :: outcome(value)
        when value: term()
  def invoke(reply_token, callback, reply, before_reply \\ fn _outcome -> :ok end)
      when is_function(callback, 0) and is_function(reply, 2) and
             is_function(before_reply, 1) do
    invoke_reply(
      reply_token,
      callback,
      fn token, outcome -> reply.(token, match?({:ok, _}, outcome)) end,
      before_reply
    )
  end

  defp capture(callback) do
    try do
      callback.() |> normalize!()
    catch
      kind, reason -> {:exception, kind, reason, __STACKTRACE__}
    end
  end

  defp observe(outcome, before_reply) do
    try do
      before_reply.(outcome)
      outcome
    catch
      kind, reason -> {:exception, kind, reason, __STACKTRACE__}
    end
  end

  defp normalize!({:ok, _value} = result), do: result
  defp normalize!({:error, _value} = result), do: result

  defp normalize!(other) do
    raise ArgumentError,
          "callback must return {:ok, value} or {:error, value}, got: #{inspect(other)}"
  end
end
