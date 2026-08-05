defmodule Mix.Tasks.Kinda.Verify do
  use Mix.Task

  @shortdoc "Verifies root tests, wrapper reporting, and the bundled example app"

  @impl Mix.Task
  def run(_args) do
    Kinda.RootVerifier.verify()
  end
end
