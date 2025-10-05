defmodule Kinda.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda,
      version: "0.10.6-dev",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
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
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:elixir_make, "~> 0.4", runtime: false}
    ]
  end

  defp description() do
    "Bind a C library to BEAM with Zig."
  end

  defp package() do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/beaver-project/kinda"},
      files: ~w{
        lib .formatter.exs mix.exs README*
        src/*.zig build.zig
      }
    ]
  end
end
