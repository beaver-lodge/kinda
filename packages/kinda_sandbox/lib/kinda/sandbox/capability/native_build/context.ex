defmodule Kinda.Sandbox.Capability.NativeBuild.Context do
  @moduledoc false

  @enforce_keys [:module, :entry_name, :directory, :env]
  defstruct [:module, :entry_name, :directory, :env]

  @type t :: %__MODULE__{
          module: module(),
          entry_name: binary(),
          directory: binary(),
          env: %{optional(binary()) => binary()}
        }
end
