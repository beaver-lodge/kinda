defmodule Kinda.SystemCommandRunner do
  @moduledoc """
  Runs external commands and turns command-boundary failures into
  `Kinda.CommandError` exceptions.
  """

  @type runner :: module() | (binary(), [binary()], keyword() -> {binary(), non_neg_integer()})

  @spec cmd(binary(), [binary()], keyword()) :: {binary(), non_neg_integer()}
  def cmd(command, args, opts) do
    System.cmd(command, args, opts)
  end

  @spec run!(runner(), binary(), [binary()], keyword(), keyword()) :: binary()
  def run!(runner, command, args, opts \\ [], context \\ []) do
    opts = Keyword.put_new(opts, :stderr_to_stdout, true)

    case invoke(runner, command, args, opts) do
      {output, 0} ->
        output

      {output, status} ->
        raise_command_error(command, args, opts, context,
          output: output,
          status: status
        )
    end
  rescue
    error in ErlangError ->
      raise_command_error(command, args, opts, context, reason: error.original)
  end

  defp invoke(runner, command, args, opts) when is_function(runner, 3),
    do: runner.(command, args, opts)

  defp invoke(runner, command, args, opts), do: runner.cmd(command, args, opts)

  defp raise_command_error(command, args, opts, context, failure) do
    raise Kinda.CommandError,
      message: Keyword.get(context, :message),
      stage: Keyword.get(context, :stage),
      command: command,
      args: args,
      cwd: Keyword.get(opts, :cd),
      status: Keyword.get(failure, :status),
      output: Keyword.get(failure, :output),
      reason: Keyword.get(failure, :reason)
  end
end
