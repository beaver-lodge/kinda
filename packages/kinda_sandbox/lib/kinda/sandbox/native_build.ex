defmodule Kinda.Sandbox.NativeBuild do
  @moduledoc "Typed facade for a sandbox backend's native build capability."

  alias Kinda.Sandbox.Capability.NativeBuild, as: NativeBuildCapability
  alias Kinda.Sandbox.{Handle, HandleServer}

  @spec build(Handle.t(), NativeBuildCapability.builder_mfa()) ::
          {:ok, binary()} | {:error, Kinda.Sandbox.Error.t()}
  def build(%Handle{ref: ref}, {_module, _function, _arguments} = builder_mfa) do
    HandleServer.native_build(ref, builder_mfa)
  end
end
