defmodule Mix.Tasks.Web3d.Showcase do
  @moduledoc "Runs and exports the Web3D Capsule showcase."

  use Mix.Task

  alias Kinda.Capsule.Web3D.Runner

  @shortdoc "Run the Web3D evaluation episode"

  @impl true
  def run(arguments) do
    {options, _remaining, _invalid} =
      OptionParser.parse(arguments, strict: [parent: :string, bundle: :string, index: :string])

    parent = Keyword.get(options, :parent, Path.expand("tmp/showcase"))
    bundle = Keyword.get(options, :bundle, Path.expand("episode", File.cwd!()))
    index = Keyword.get(options, :index, bundle <> ".sqlite3")
    File.mkdir_p!(parent)

    Mix.Task.run("app.start")

    case Runner.run(parent_directory: parent, bundle: bundle, index: index) do
      {:ok, result} ->
        Mix.shell().info("Exported #{result.bundle} and #{result.index} (#{result.digest})")

      {:error, reason} ->
        Mix.raise("showcase failed: #{inspect(reason)}")
    end
  end
end
