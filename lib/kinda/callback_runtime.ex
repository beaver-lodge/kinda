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
  @spec invoke_reply(term(), (-> callback_result(v)), (term(), outcome(v) -> term()), (outcome(v) -> term())) ::
          outcome(v)
        when v: term()
  def invoke_reply(reply_token, callback, reply, before_reply \\ fn _outcome -> :ok end)
      when is_function(callback, 0) and is_function(reply, 2) and
             is_function(before_reply, 1) do
    outcome = callback |> capture() |> observe(before_reply)
    reply.(reply_token, outcome)
    outcome
  end

  @spec invoke(term(), (-> callback_result(v)), (term(), boolean() -> term()), (outcome(v) -> term())) ::
          outcome(v)
        when v: term()
  def invoke(reply_token, callback, reply, before_reply \\ fn _outcome -> :ok end)
      when is_function(callback, 0) and is_function(reply, 2) and
             is_function(before_reply, 1),
      do: invoke_reply(reply_token, callback, &reply.(&1, match?({:ok, _}, &2)), before_reply)

  defp capture(callback) do
    callback.() |> normalize!()
  catch
    kind, reason -> {:exception, kind, reason, __STACKTRACE__}
  end

  defp observe(outcome, before_reply) do
    before_reply.(outcome)
    outcome
  catch
    kind, reason -> {:exception, kind, reason, __STACKTRACE__}
  end

  defp normalize!({status, _value} = result) when status in [:ok, :error], do: result

  defp normalize!(other) do
    raise ArgumentError,
          "callback must return {:ok, value} or {:error, value}, got: #{inspect(other)}"
  end
end
