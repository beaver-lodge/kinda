defmodule Kinda.Sandbox.Command.Spec do
  @moduledoc "A shell-free command specification: executable and arguments are always distinct."

  alias Kinda.Sandbox.Error

  @enforce_keys [:executable]
  defstruct executable: nil,
            args: [],
            cwd: ".",
            env: %{},
            inherit_env: [],
            stdin: :closed,
            timeout: 30_000,
            terminate_after: 5_000,
            max_output_bytes: 1_000_000

  @type t :: %__MODULE__{
          executable: binary(),
          args: [binary()],
          cwd: binary(),
          env: %{optional(binary()) => binary()},
          inherit_env: [binary()],
          stdin: :closed | binary(),
          timeout: pos_integer() | :infinity,
          terminate_after: non_neg_integer(),
          max_output_bytes: non_neg_integer()
        }

  @spec validate(t()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = spec) do
    checks = [
      {valid_string?(spec.executable), "executable must be a non-empty string"},
      {valid_strings?(spec.args), "args must contain strings without NUL bytes"},
      {valid_relative_cwd?(spec.cwd), "cwd must be a relative path inside the sandbox"},
      {valid_env?(spec.env), "env must contain string keys and values without NUL bytes"},
      {valid_strings?(spec.inherit_env), "inherit_env must contain strings without NUL bytes"},
      {valid_stdin?(spec.stdin), "stdin must be :closed or a binary"},
      {valid_timeout?(spec.timeout), "timeout must be a positive integer or :infinity"},
      {is_integer(spec.terminate_after) and spec.terminate_after >= 0,
       "terminate_after must be a non-negative integer"},
      {is_integer(spec.max_output_bytes) and spec.max_output_bytes >= 0,
       "max_output_bytes must be a non-negative integer"}
    ]

    case Enum.find(checks, fn {valid?, _message} -> not valid? end) do
      nil -> :ok
      {_valid?, message} -> invalid(message)
    end
  end

  def validate(_spec), do: invalid("expected a Kinda.Sandbox.Command.Spec")

  defp valid_string?(value),
    do: is_binary(value) and value != "" and not String.contains?(value, <<0>>)

  defp valid_strings?(values) when is_list(values), do: Enum.all?(values, &valid_string?/1)
  defp valid_strings?(_values), do: false

  defp valid_relative_cwd?(cwd) when is_binary(cwd) do
    not String.contains?(cwd, <<0>>) and
      cwd != "" and
      Path.type(cwd) != :absolute and
      not Enum.member?(Path.split(cwd), "..")
  end

  defp valid_relative_cwd?(_cwd), do: false

  defp valid_env?(env) when is_map(env) do
    Enum.all?(env, fn {key, value} ->
      valid_string?(key) and is_binary(value) and not String.contains?(value, <<0>>)
    end)
  end

  defp valid_env?(_env), do: false
  defp valid_stdin?(:closed), do: true
  defp valid_stdin?(stdin), do: is_binary(stdin)
  defp valid_timeout?(:infinity), do: true
  defp valid_timeout?(timeout), do: is_integer(timeout) and timeout > 0

  defp invalid(message) do
    {:error, Error.exception(reason: :invalid_spec, operation: :command, message: message)}
  end
end
