defmodule Kinda.Capsule.Web3D.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda_capsule_web3d,
      version: "0.1.0-dev",
      elixir: "~> 1.20",
      deps: deps(),
      name: "Kinda Capsule Web3D Showcase",
      description: "Auditable Web3D agent-evaluation episode showcase"
    ]
  end

  def application, do: [extra_applications: [:crypto, :logger]]

  defp deps do
    [
      {:kinda_capsule, path: "../kinda_capsule"},
      {:kinda_sqlite, path: "../kinda_sqlite"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
