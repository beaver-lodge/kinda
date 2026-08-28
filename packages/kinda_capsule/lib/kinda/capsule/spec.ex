defmodule Kinda.Capsule.Spec do
  @moduledoc "Static task, verifier, Sandbox, and episode limits."

  alias Kinda.Capsule.{Error, RuntimeFingerprint, SandboxSpec}

  @enforce_keys [:task, :task_version, :verifier, :verifier_version, :sandbox]
  defstruct [
    :task,
    :task_version,
    :verifier,
    :verifier_version,
    :sandbox,
    capsule_version: "0.1.0",
    fixture_digest: "unspecified",
    verifier_source_digest: "unspecified",
    verifier_executable_digest: "unspecified",
    runtime: %RuntimeFingerprint{},
    model: %{},
    task_options: [],
    verifier_options: [],
    max_steps: 100
  ]

  @type t :: %__MODULE__{
          task: module(),
          task_version: binary(),
          task_options: keyword(),
          verifier: module(),
          verifier_version: binary(),
          verifier_options: keyword(),
          sandbox: SandboxSpec.t(),
          capsule_version: binary(),
          fixture_digest: binary(),
          verifier_source_digest: binary(),
          verifier_executable_digest: binary(),
          runtime: RuntimeFingerprint.t(),
          model: map(),
          max_steps: pos_integer()
        }

  @spec validate(t()) :: :ok | {:error, Error.t()}
  def validate(%__MODULE__{} = spec) do
    checks = [
      {valid_callback?(spec.task, :reset, 3), "task must implement reset/3"},
      {valid_callback?(spec.task, :observe, 2), "task must implement observe/2"},
      {valid_callback?(spec.task, :close, 2), "task must implement close/2"},
      {valid_version?(spec.task_version), "task_version must be a non-empty string"},
      {Keyword.keyword?(spec.task_options), "task_options must be a keyword list"},
      {valid_callback?(spec.verifier, :grade, 2), "verifier must implement grade/2"},
      {valid_version?(spec.verifier_version), "verifier_version must be a non-empty string"},
      {valid_version?(spec.capsule_version), "capsule_version must be a non-empty string"},
      {valid_version?(spec.fixture_digest), "fixture_digest must be a non-empty string"},
      {valid_version?(spec.verifier_source_digest),
       "verifier_source_digest must be a non-empty string"},
      {valid_version?(spec.verifier_executable_digest),
       "verifier_executable_digest must be a non-empty string"},
      {RuntimeFingerprint.valid?(spec.runtime), "runtime must be a valid runtime fingerprint"},
      {is_map(spec.model), "model must be a map"},
      {Keyword.keyword?(spec.verifier_options), "verifier_options must be a keyword list"},
      {valid_sandbox?(spec.sandbox), "sandbox must contain a backend module and keyword options"},
      {is_integer(spec.max_steps) and spec.max_steps > 0, "max_steps must be a positive integer"}
    ]

    case Enum.find(checks, fn {valid?, _message} -> not valid? end) do
      nil -> :ok
      {_valid?, message} -> invalid(message)
    end
  end

  def validate(_spec), do: invalid("expected a Kinda.Capsule.Spec")

  defp valid_callback?(module, function, arity) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  defp valid_callback?(_module, _function, _arity), do: false

  defp valid_version?(version), do: is_binary(version) and version != ""

  defp valid_sandbox?(%SandboxSpec{backend: backend, backend_options: options}) do
    is_atom(backend) and Code.ensure_loaded?(backend) and Keyword.keyword?(options)
  end

  defp valid_sandbox?(_sandbox), do: false

  defp invalid(message) do
    {:error, Error.exception(phase: :create, reason: :invalid_spec, message: message)}
  end
end
