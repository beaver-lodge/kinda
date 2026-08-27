defmodule Kinda.Capsule.SandboxSpec do
  @moduledoc "Typed selection of a Sandbox backend and its private spec."

  @enforce_keys [:backend, :backend_spec]
  defstruct [:backend, :backend_spec, backend_options: []]

  @type t :: %__MODULE__{
          backend: module(),
          backend_spec: term(),
          backend_options: keyword()
        }
end
