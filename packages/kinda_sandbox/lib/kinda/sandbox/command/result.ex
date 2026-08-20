defmodule Kinda.Sandbox.Command.Result do
  @moduledoc "Terminal result of a sandbox command execution."

  @enforce_keys [:termination, :stdout, :stderr, :duration]
  defstruct [
    :termination,
    :stdout,
    :stderr,
    :duration,
    stdout_truncated?: false,
    stderr_truncated?: false,
    metadata: %{}
  ]

  @type termination ::
          {:exit, non_neg_integer()}
          | {:signal, non_neg_integer()}
          | :cancelled
          | :timeout
          | :spawn_failure
  @type t :: %__MODULE__{
          termination: termination(),
          stdout: binary(),
          stderr: binary(),
          duration: non_neg_integer(),
          stdout_truncated?: boolean(),
          stderr_truncated?: boolean(),
          metadata: map()
        }
end
