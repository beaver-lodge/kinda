defmodule Kinda.Capsule.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda_capsule,
      version: "0.1.0-dev",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Kinda Capsule",
      description: "Owner-scoped typed episode runtime built on Kinda Sandbox"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Kinda.Capsule.Application, []}
    ]
  end

  defp deps do
    [
      {:kinda_sandbox, path: "../kinda_sandbox"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:telemetry, "~> 1.3"}
    ]
  end
end
