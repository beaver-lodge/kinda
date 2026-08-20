defmodule Kinda.Sandbox.Shell do
  @moduledoc """
  Explicit shell adapter over `Kinda.Sandbox.Command`.

  The adapter never consults `$SHELL`, never falls back to a different
  interpreter, and never injects shell error-handling policy into the script.
  """

  alias Kinda.Sandbox.Command
  alias Kinda.Sandbox.Command.{Result, Spec}
  alias Kinda.Sandbox.{Error, Handle}

  @type interpreter :: :posix_sh | :bash | :zsh | {:path, binary(), [binary()]}

  @command_options [:cwd, :env, :inherit_env, :stdin, :timeout, :max_output_bytes]
  @options [:interpreter, :await_timeout | @command_options]

  @spec run(Handle.t(), binary(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(%Handle{} = sandbox, script, options \\ []) do
    with :ok <- validate_script(script),
         :ok <- validate_options(options),
         {:ok, executable, arguments, profile} <- interpreter(options),
         spec <- command_spec(executable, arguments, script, options),
         {:ok, result} <-
           Command.run(sandbox, spec, Keyword.get(options, :await_timeout, :infinity)) do
      shell = %{profile: profile, executable: executable, version: nil}
      {:ok, %{result | metadata: Map.put(result.metadata, :shell, shell)}}
    end
  end

  defp interpreter(options) do
    case Keyword.get(options, :interpreter, :posix_sh) do
      :posix_sh -> resolve(:posix_sh, "sh", [])
      :bash -> resolve(:bash, "bash", ["--noprofile", "--norc"])
      :zsh -> resolve(:zsh, "zsh", ["-f"])
      {:path, path, arguments} -> exact(path, arguments)
      other -> invalid("invalid shell interpreter", other)
    end
  end

  defp resolve(profile, name, arguments) do
    case System.find_executable(name) do
      nil ->
        {:error,
         Error.exception(
           reason: :unsupported_capability,
           operation: :shell,
           message: "requested shell interpreter is unavailable",
           details: %{interpreter: profile}
         )}

      executable ->
        {:ok, executable, arguments, profile}
    end
  end

  defp exact(path, arguments)
       when is_binary(path) and path != "" and is_list(arguments) do
    if valid_strings?([path | arguments]) do
      {:ok, path, arguments, {:path, path, arguments}}
    else
      invalid("shell path and arguments must be strings without NUL bytes", {path, arguments})
    end
  end

  defp exact(path, arguments),
    do: invalid("invalid exact shell interpreter", {path, arguments})

  defp command_spec(executable, interpreter_arguments, script, options) do
    fields =
      options
      |> Keyword.take(@command_options)
      |> Keyword.put(:executable, executable)
      |> Keyword.put(:args, interpreter_arguments ++ ["-c", script])

    struct!(Spec, fields)
  end

  defp validate_script(script) when is_binary(script) and script != "" do
    if String.contains?(script, <<0>>),
      do: invalid("shell script must not contain NUL bytes", script),
      else: :ok
  end

  defp validate_script(script), do: invalid("shell script must be a non-empty binary", script)

  defp validate_options(options) when is_list(options) do
    case Keyword.keys(options) -- @options do
      [] -> :ok
      unknown -> invalid("unknown shell options", unknown)
    end
  end

  defp validate_options(options), do: invalid("shell options must be a keyword list", options)

  defp valid_strings?(strings) do
    Enum.all?(strings, &(is_binary(&1) and &1 != "" and not String.contains?(&1, <<0>>)))
  end

  defp invalid(message, details) do
    {:error,
     Error.exception(
       reason: :invalid_spec,
       operation: :shell,
       message: message,
       details: details
     )}
  end
end
