defmodule Kinda.Capsule.CommandSummary do
  @moduledoc "Safe trace projection of a command action."

  @enforce_keys [:executable, :args, :cwd, :env_keys, :inherit_env, :stdin_bytes]
  defstruct [:executable, :args, :cwd, :env_keys, :inherit_env, :stdin_bytes]

  @type t :: %__MODULE__{
          executable: binary(),
          args: [binary()],
          cwd: binary(),
          env_keys: [binary()],
          inherit_env: [binary()],
          stdin_bytes: non_neg_integer()
        }
end
