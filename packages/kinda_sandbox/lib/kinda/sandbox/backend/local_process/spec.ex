defmodule Kinda.Sandbox.Backend.LocalProcess.Spec do
  @moduledoc "Specification for a local process workspace."

  defstruct [:parent_directory, env: %{}]

  @type t :: %__MODULE__{
          parent_directory: binary() | nil,
          env: %{optional(binary()) => binary()}
        }
end
