defmodule EctoKindaSQLite.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_kinda_sqlite,
      version: "0.1.0-dev",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Ecto Kinda SQLite",
      description: "An Ecto SQL adapter backed by Kinda SQLite",
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.14"},
      {:ecto_sqlite3, "~> 0.24.1"},
      {:jason, "~> 1.4"},
      {:kinda_sqlite, path: "../kinda_sqlite"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
