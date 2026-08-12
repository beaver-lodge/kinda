defmodule Kinda.Testing.Isolated.Runner do
  @moduledoc false

  def main do
    with <<size::unsigned-big-32>> <- IO.binread(:stdio, 4),
         payload when is_binary(payload) <- IO.binread(:stdio, size) do
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
    IO.binwrite(:stdio, <<byte_size(payload)::unsigned-big-32, payload::binary>>)
  end
end
