defmodule Mix.Tasks.Kinda.Python.Verify do
  use Mix.Task

  @shortdoc "Verifies the Kinda Python package from the repo root"

  @impl Mix.Task
  def run(_args) do
    Kinda.ExampleVerifier.verify(relative_path: "packages/kinda_python")
  end
end
