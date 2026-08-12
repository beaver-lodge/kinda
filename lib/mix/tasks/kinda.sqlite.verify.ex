defmodule Mix.Tasks.Kinda.Sqlite.Verify do
  use Mix.Task

  @shortdoc "Verifies the Kinda SQLite driver from the repo root"

  @impl Mix.Task
  def run(_args) do
    Kinda.ExampleVerifier.verify(relative_path: "packages/kinda_sqlite")
  end
end
