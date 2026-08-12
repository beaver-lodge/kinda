defmodule Kinda.Lua.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda_lua,
      version: "0.1.0-dev",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Kinda Lua",
      description: "A multi-instance embedded Lua runtime built with Kinda",
      compilers: [:elixir_make] ++ Mix.compilers()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.4", runtime: false},
      {:kinda, path: "../.."}
    ]
  end
end
