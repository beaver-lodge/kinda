defmodule KindaExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :kinda_example,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:cmake] ++ Mix.compilers(),
      aliases: aliases()
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
      {:kinda, path: ".."}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  require Logger

  defp do_cmake() do
    cmake_project = "native/c-src"
    build = Path.join(Mix.Project.app_path(), "cmake-build")
    install = Path.join(Mix.Project.app_path(), "native-install")

    Logger.debug("[CMake] configuring...")

    {_, 0} =
      System.cmd(
        "cmake",
        [
          "-S",
          cmake_project,
          "-B",
          build,
          "-G",
          "Ninja",
          "-DCMAKE_INSTALL_PREFIX=#{install}"
        ],
        stderr_to_stdout: true
      )

    Logger.debug("[CMake] building...")

    with {_, 0} <- System.cmd("cmake", ["--build", build, "--target", "install"]) do
      Logger.debug("[CMake] installed to #{install}")
      :ok
    else
      {error, _} ->
        Logger.error(error)
        {:error, [error]}
    end
  end

  defp cmake(args) do
    if "--force" in args do
      do_cmake()
    else
      :noop
    end
  end

  defp aliases do
    ["compile.cmake": &cmake/1]
  end
end
