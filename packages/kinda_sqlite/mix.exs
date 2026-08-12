defmodule Kinda.SQLite.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda_sqlite,
      version: "0.1.0-dev",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Kinda SQLite",
      description: "A SQLite driver built with Kinda",
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
      {:kinda, path: "../.."},
      {:kinda_example, path: "../kinda_example", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:db_connection, "~> 2.10"},
      {:elixir_make, "~> 0.4", runtime: false}
    ]
  end
end
