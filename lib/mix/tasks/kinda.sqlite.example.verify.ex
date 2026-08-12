defmodule Mix.Tasks.Kinda.Sqlite.Example.Verify do
  use Mix.Task

  @shortdoc "Verifies the bundled SQLite example app from the repo root"

  @impl Mix.Task
  def run(_args) do
    Kinda.ExampleVerifier.verify(relative_path: "kinda_sqlite_example")
  end
end
