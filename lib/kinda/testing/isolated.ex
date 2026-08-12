defmodule Kinda.Testing.Isolated do
  @moduledoc """
  Runs an MFA in a fresh BEAM VM.

  Requests and replies use packet-4 framed ETF over a port. This keeps tests
  with VM-global state parallel at the ExUnit level without sharing that state.
  """

  @type scenario :: {module(), atom(), [term()]}

  @spec run(scenario(), keyword()) :: term()
  def run({module, function, arguments} = scenario, options \\ [])
      when is_atom(module) and is_atom(function) and is_list(arguments) do
    timeout = Keyword.get(options, :timeout, 30_000)
    executable = Keyword.get_lazy(options, :executable, &elixir_executable!/0)
    paths = Keyword.get(options, :code_paths, :code.get_path())

    args =
      Enum.flat_map(paths, &["-pa", List.to_string(&1)]) ++
        ["-e", "Kinda.Testing.Isolated.Runner.main()"]

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        {:packet, 4},
        {:args, args}
      ])

    true = Port.command(port, :erlang.term_to_binary(scenario))
    receive_result(port, timeout)
  end

  defp receive_result(port, timeout) do
    receive do
      {^port, {:data, payload}} ->
        decode_result(:erlang.binary_to_term(payload))

      {^port, {:exit_status, status}} ->
        raise "isolated BEAM exited before replying (status #{status})"
    after
      timeout ->
        Port.close(port)
        raise "isolated BEAM timed out after #{timeout}ms"
    end
  end

  defp decode_result({:ok, value}), do: value

  defp decode_result({:exception, kind, reason, stacktrace}) do
    message = Exception.format(kind, reason, stacktrace)
    raise RuntimeError, "isolated BEAM failed:\n#{message}"
  end

  defp elixir_executable! do
    System.find_executable("elixir") || raise "cannot find the elixir executable"
  end
end
