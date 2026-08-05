deps = [{:kinda, path: Path.expand("..", __DIR__)}]

deps =
  if Version.match?(System.version(), "< 1.18.0") do
    [{:jason, "~> 1.4"} | deps]
  else
    deps
  end

Mix.install(deps, force: true)

Kinda.Wrapper.Example.run()
