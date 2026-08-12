defmodule Mix.Tasks.Kinda.Verify do
  use Mix.Task

  @shortdoc "Verifies root tests, reporting, and all bundled example apps"

  @impl Mix.Task
  def run(_args) do
    Kinda.RootVerifier.verify()
  end
end
