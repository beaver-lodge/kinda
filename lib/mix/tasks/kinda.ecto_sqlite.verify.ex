defmodule Mix.Tasks.Kinda.EctoSqlite.Verify do
  use Mix.Task

  @shortdoc "Verifies the Kinda SQLite Ecto adapter from the repo root"

  @impl Mix.Task
  def run(_args) do
    Kinda.ExampleVerifier.verify(relative_path: "packages/ecto_kinda_sqlite")
  end
end
