defmodule Mix.Tasks.Kinda.Duckdb.Verify do
  use Mix.Task

  @shortdoc "Verifies the Kinda DuckDB driver from the repo root"

  @impl Mix.Task
  def run(_args) do
    Kinda.ExampleVerifier.verify(relative_path: "packages/kinda_duckdb")
  end
end
