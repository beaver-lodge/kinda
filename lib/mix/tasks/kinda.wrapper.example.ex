defmodule Mix.Tasks.Kinda.Wrapper.Example do
  use Mix.Task

  @shortdoc "Prints the wrapper reporting example"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          json: :boolean,
          report_only: :boolean
        ]
      )

    Kinda.Wrapper.Example.run(opts)
  end
end
