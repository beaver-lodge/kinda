defmodule Mix.Tasks.Kinda.Example.Verify do
  use Mix.Task

  @shortdoc "Verifies the bundled kinda_example app from the repo root"

  @impl Mix.Task
  def run(_args) do
    example_verifier().verify()
  end

  defp example_verifier do
    Application.get_env(:kinda, :example_verifier, Kinda.ExampleVerifier)
  end
end
