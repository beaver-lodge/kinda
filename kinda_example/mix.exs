defmodule KindaExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda_example,
      version: "0.1.0-dev",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers()
    ] ++
      [
        make_precompiler: {:nif, Kinda.Precompiler},
        make_precompiler_url: "http://127.0.0.1:8000/@{artefact_filename}"
      ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:kinda, path: ".."},
      {:elixir_make, "~> 0.4", runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  require Logger
end
