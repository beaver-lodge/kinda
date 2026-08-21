defmodule Kinda.Sandbox.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda_sandbox,
      version: "0.1.0-dev",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Kinda Sandbox",
      description: "Backend-neutral lifecycle and capability contracts for Kinda sandboxes",
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_precompiler: {:nif, Kinda.Precompiler},
      make_precompiler_url: "http://127.0.0.1:8000/@{artefact_filename}"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Kinda.Sandbox.Application, []}
    ]
  end

  defp deps do
    [
      {:kinda, path: "../.."},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.4", runtime: false},
      {:ex_cmd, "~> 0.18"},
      {:telemetry, "~> 1.3"}
    ]
  end
end
