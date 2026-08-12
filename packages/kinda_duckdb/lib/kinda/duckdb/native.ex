defmodule Kinda.DuckDB.Native do
  @moduledoc false

  alias Kinda.DuckDB.WindowsLoader

  @on_load :load_nif

  def library_version, do: :erlang.nif_error({:nif_not_loaded, :library_version})

  def query_int64(_database, _sql),
    do: :erlang.nif_error({:nif_not_loaded, :query_int64})

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:kinda_duckdb)}/lib/libKindaDuckDBNIF"
    dylib = "#{nif_file}.dylib"

    preload_windows_runtime()

    if File.exists?(dylib) do
      File.ln_s(dylib, "#{nif_file}.so")
    end

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _message}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp preload_windows_runtime do
    if match?({:win32, _name}, :os.type()) do
      runtime = :kinda_duckdb |> :code.priv_dir() |> Path.join("lib/duckdb.dll")
      :ok = WindowsLoader.load_nif()
      :ok = WindowsLoader.load_library(runtime)
    end
  end
end
