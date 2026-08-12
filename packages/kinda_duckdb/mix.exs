defmodule Kinda.DuckDB.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda_duckdb,
      version: "0.1.0-dev",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Kinda DuckDB",
      description: "A DuckDB driver built with Kinda",
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_precompiler: {:nif, Kinda.Precompiler},
      make_precompiler_url: "http://127.0.0.1:8000/@{artefact_filename}"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:db_connection, "~> 2.10"},
      {:elixir_make, "~> 0.4", runtime: false},
      {:kinda, path: "../.."},
      {:kinda_sqlite, path: "../kinda_sqlite", only: :test}
    ]
  end
end
