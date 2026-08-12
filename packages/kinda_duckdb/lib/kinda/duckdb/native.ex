defmodule Kinda.DuckDB.Native do
  @moduledoc false

  alias Kinda.DuckDB.WindowsLoader

  @on_load :load_nif

  for {name, arity} <- [
        library_version: 0,
        query_int64: 2,
        open: 1,
        close_database: 1,
        connect: 1,
        close_connection: 1,
        query: 2,
        close_result: 1,
        prepare: 2,
        close_prepared: 1,
        bind_prepared: 2,
        create_pending: 2,
        close_pending: 1,
        pending_task: 1,
        pending_error: 1,
        execute_pending: 1,
        interrupt: 1,
        result_column_count: 1,
        result_row_count: 1,
        result_rows_changed: 1,
        result_column_name: 2,
        result_value: 3,
        create_appender: 2,
        close_appender: 1,
        append_row: 2,
        append_begin: 1,
        append_end: 1,
        append_null: 1,
        append_bool: 2,
        append_int64: 2,
        append_double: 2,
        append_varchar: 2,
        flush_appender: 1
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)

    def unquote(name)(unquote_splicing(args)),
      do: :erlang.nif_error({:nif_not_loaded, unquote(name)})
  end

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
