defmodule Mix.Tasks.Kinda.Dist do
  @moduledoc "Printed when the user requests `mix help echo`"
  @shortdoc "Echoes arguments"

  use Mix.Task

  defp gen_cwd(lib) do
    ["-C", Path.dirname(lib) |> Path.absname, Path.basename(lib)]
  end
  @impl Mix.Task
  def run([nif_lib]) do

    if not File.exists?(nif_lib) do
      Mix.raise("NIF library #{nif_lib} does not exist")
    end
    if Path.extname(nif_lib) == "so" do
      Mix.raise("NIF library #{nif_lib} not a so file")
    end
    base_name = Path.basename(nif_lib)
    dir_name = Path.dirname(nif_lib)
    tar_name = base_name <> ".tar.gz"

    solibs = Path.join([dir_name, "**", "*.so"]) |> Path.wildcard()
    dylibs =
      case :os.type() do
        {:unix, :darwin} ->
       Path.join([dir_name, "**", "*.dylib"]) |> Path.wildcard()
      _ ->
       []
      end
    exs = Path.join([dir_name, ".." , "**", "kinda-meta-*.ex"]) |> Path.wildcard()
    cwds = (solibs ++ dylibs ++ exs) |> Enum.map(&gen_cwd/1) |> List.flatten()
    System.cmd("tar", ["--dereference", "-cvzf", tar_name] ++ cwds)
  end
end
