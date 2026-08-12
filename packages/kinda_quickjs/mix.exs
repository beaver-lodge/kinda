defmodule Kinda.QuickJS.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda_quickjs,
      version: "0.1.0-dev",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Kinda QuickJS",
      description: "A multi-instance embedded QuickJS runtime built with Kinda",
      compilers: [:elixir_make] ++ Mix.compilers()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.4", runtime: false},
      {:kinda, path: "../.."},
      {:kinda_duckdb, path: "../kinda_duckdb", only: :test},
      {:kinda_lua, path: "../kinda_lua", only: :test},
      {:kinda_mruby, path: "../kinda_mruby", only: :test},
      {:kinda_python, path: "../kinda_python", only: :test},
      {:kinda_sqlite, path: "../kinda_sqlite", only: :test}
    ]
  end
end
