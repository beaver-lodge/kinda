defmodule Kinda.Sandbox.Backend.LocalNative.Spec do
  @moduledoc "Specification for an isolated local native build directory."

  @enforce_keys [:base_module]
  defstruct [:base_module, :parent_directory, env: %{}]

  @type t :: %__MODULE__{
          base_module: module(),
          parent_directory: binary() | nil,
          env: %{optional(binary()) => binary()}
        }
end
