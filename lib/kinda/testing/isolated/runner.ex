defmodule Kinda.Testing.Isolated.Runner do
  @moduledoc false
  @reply_marker "KINDA_ISOLATED_REPLY\0"

  def main do
    :ok = :io.setopts(:standard_io, [:binary, encoding: :latin1])

    with <<size::unsigned-big-32>> <- IO.binread(:stdio, 4),
         encoded when is_binary(encoded) <- IO.binread(:stdio, size),
         {:ok, payload} <- Base.decode64(encoded) do
      payload
      |> :erlang.binary_to_term()
      |> execute()
      |> reply()
    else
      other -> reply({:exception, :error, {:invalid_request, other}, []})
    end
  end

  defp execute({module, function, arguments}) do
    {:ok, apply(module, function, arguments)}
  catch
    kind, reason -> {:exception, kind, reason, __STACKTRACE__}
  end

  defp reply(term) do
    payload = :erlang.term_to_binary(term)

    IO.binwrite(
      :stdio,
      <<@reply_marker::binary, byte_size(payload)::unsigned-big-32, payload::binary>>
    )
  end
end
