defmodule Kinda.Testing.Isolated do
  @moduledoc """
  Runs an MFA in a fresh BEAM VM.

  Requests and replies use ETF over a port. Replies carry a marker so arbitrary
  stdout from embedded native runtimes cannot corrupt the control channel. This
  keeps tests with VM-global state parallel without sharing that state.
  """

  @type scenario :: {module(), atom(), [term()]}
  @reply_marker "KINDA_ISOLATED_REPLY\0"

  @spec run(scenario(), keyword()) :: term()
  def run({module, function, arguments} = scenario, options \\ [])
      when is_atom(module) and is_atom(function) and is_list(arguments) do
    timeout = Keyword.get(options, :timeout, 30_000)
    executable = Keyword.get_lazy(options, :executable, &elixir_executable!/0)
    paths = Keyword.get(options, :code_paths, :code.get_path())
    working_directory = Keyword.get(options, :working_directory, System.tmp_dir!())

    args =
      paths
      |> Enum.map(&Path.expand(List.to_string(&1)))
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])
      |> Kernel.++(["-e", "Kinda.Testing.Isolated.Runner.main()"])

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        {:cd, working_directory},
        {:args, args}
      ])

    payload = scenario |> :erlang.term_to_binary() |> Base.encode64()
    true = Port.command(port, <<byte_size(payload)::unsigned-big-32, payload::binary>>)
    receive_result(port, timeout, <<>>)
  end

  defp receive_result(port, timeout, buffer) do
    receive do
      {^port, {:data, payload}} ->
        buffer = buffer <> payload

        case extract_reply(buffer) do
          {:ok, result} -> decode_result(result)
          :more -> receive_result(port, timeout, buffer)
        end

      {^port, {:exit_status, status}} ->
        raise "isolated BEAM exited before replying (status #{status})"
    after
      timeout ->
        Port.close(port)
        raise "isolated BEAM timed out after #{timeout}ms"
    end
  end

  defp extract_reply(buffer) do
    case :binary.match(buffer, @reply_marker) do
      {offset, marker_size} ->
        framed =
          binary_part(buffer, offset + marker_size, byte_size(buffer) - offset - marker_size)

        extract_framed_reply(framed)

      :nomatch ->
        :more
    end
  end

  defp extract_framed_reply(<<size::unsigned-big-32, payload::binary-size(size), _rest::binary>>) do
    {:ok, :erlang.binary_to_term(payload)}
  end

  defp extract_framed_reply(_incomplete), do: :more

  defp decode_result({:ok, value}), do: value

  defp decode_result({:exception, kind, reason, stacktrace}) do
    message = Exception.format(kind, reason, stacktrace)
    raise RuntimeError, "isolated BEAM failed:\n#{message}"
  end

  defp elixir_executable! do
    System.find_executable("elixir") || raise "cannot find the elixir executable"
  end
end
