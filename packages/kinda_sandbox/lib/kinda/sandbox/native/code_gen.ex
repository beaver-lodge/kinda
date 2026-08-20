defmodule Kinda.Sandbox.Native.CodeGen do
  @moduledoc false

  alias Kinda.CodeGen.{DeclarationManifest, NIFDecl}

  @behaviour Kinda.CodeGen

  @impl true
  def declaration_manifest do
    DeclarationManifest.build([
      %NIFDecl{wrapper_name: :spawn, params: [:executable, :args, :cwd, :env, :stdin]},
      %NIFDecl{wrapper_name: :read_event, params: [:process], dirty: :dirty_io},
      %NIFDecl{
        wrapper_name: :terminate,
        params: [:process, :grace_milliseconds],
        dirty: :dirty_io
      }
    ])
  end
end
