defmodule Kinda.SQLite.Native do
  @moduledoc false

  @on_load :load_nif

  for {name, arity} <- [
        open: 1,
        open_memory: 0,
        close: 1,
        execute: 2,
        prepare: 2,
        finalize: 1,
        reset: 1,
        clear_bindings: 1,
        bind_null: 2,
        bind_int64: 3,
        bind_double: 3,
        bind_text: 3,
        bind_blob: 3,
        step: 1,
        column_count: 1,
        column_name: 2,
        column_type: 2,
        column_int64: 2,
        column_double: 2,
        column_text: 2,
        column_blob: 2,
        database_changes: 1,
        last_insert_rowid: 1,
        interrupt: 1,
        error_info: 1,
        sqlite_version: 0,
        lifecycle_stats: 0,
        scalar_make: 1,
        scalar_value: 1
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)

    def unquote(name)(unquote_splicing(args)),
      do: :erlang.nif_error({:nif_not_loaded, unquote(name)})
  end

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:kinda_sqlite)}/lib/libKindaSQLiteNIF"

    dylib = "#{nif_file}.dylib"

    if File.exists?(dylib) do
      File.ln_s(dylib, "#{nif_file}.so")
    end

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
