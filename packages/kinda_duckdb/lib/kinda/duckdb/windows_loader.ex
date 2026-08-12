defmodule Kinda.DuckDB.WindowsLoader do
  @moduledoc false

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:kinda_duckdb)}/lib/libKindaDuckDBLoaderNIF"

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _message}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def load_library(_path), do: :erlang.nif_error({:nif_not_loaded, :load_library})
end
