defmodule Kinda.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda,
      version: "0.12.0-dev",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      docs: docs(),
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:elixir_make, "~> 0.4", runtime: false},
      {:jason, "~> 1.4"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp description() do
    "Bind a C library to BEAM with Zig."
  end

  defp docs do
    [
      main: "Kinda",
      source_url: "https://github.com/beaver-lodge/kinda",
      homepage_url: "https://github.com/beaver-lodge/kinda",
      extras: ["README.md"],
      filter_modules: fn module, _metadata ->
        not String.starts_with?(Atom.to_string(module), "Mix.Tasks.")
      end,
      groups_for_modules: [
        Core: [
          Kinda,
          Kinda.CallError,
          Kinda.CommandError,
          Kinda.CallbackRuntime,
          Kinda.Codec,
          Kinda.Declaration,
          Kinda.GenerationError,
          Kinda.NIFLoadError,
          Kinda.Resource.Declaration,
          Kinda.ResourceKind
        ],
        Codegen: [
          Kinda.CodeGen,
          Kinda.CodeGen.DeclarationManifest,
          Kinda.CodeGen.DeclarationSurfaces,
          Kinda.CodeGen.KindDecl,
          Kinda.CodeGen.NIFDecl,
          Kinda.CodeGen.TypeDecl,
          Kinda.CodeGen.TypeSpecRef
        ],
        "Wrapper extraction": [
          Kinda.Wrapper.CField,
          Kinda.Wrapper.CRecord,
          Kinda.Wrapper.CType,
          Kinda.Wrapper.CallbackBridge,
          Kinda.Wrapper.Example,
          Kinda.Wrapper.Extract,
          Kinda.Wrapper.Function,
          Kinda.Wrapper.Generate,
          Kinda.Wrapper.Manifest,
          Kinda.Wrapper.Policy
        ],
        Verification: [
          Kinda.ExampleVerifier,
          Kinda.RootVerifier,
          Kinda.SystemCommandRunner
        ],
        Testing: [
          Kinda.Testing.Isolated,
          Kinda.Testing.Lifecycle,
          Kinda.Testing.NativeScenario,
          Kinda.Testing.NIFUpgrade
        ],
        Precompilation: [
          Kinda.Prebuilt.Meta,
          Kinda.Precompiler
        ]
      ]
    ]
  end

  defp package() do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/beaver-lodge/kinda"},
      files: ~w{
        lib .formatter.exs mix.exs README*
        src/*.zig build.zig build.zig.zon
        scripts/gdb.sh
      }
    ]
  end
end
