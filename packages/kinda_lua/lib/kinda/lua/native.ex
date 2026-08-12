defmodule Kinda.Lua.Native do
  @moduledoc false
  @on_load :load_nif

  def version, do: :erlang.nif_error({:nif_not_loaded, :version})
  def eval(_code), do: :erlang.nif_error({:nif_not_loaded, :eval})
  def create_vm(_budget), do: :erlang.nif_error({:nif_not_loaded, :create_vm})
  def eval_vm(_vm, _code), do: :erlang.nif_error({:nif_not_loaded, :eval_vm})
  def close_vm(_vm), do: :erlang.nif_error({:nif_not_loaded, :close_vm})
  def allocator_stats(_vm), do: :erlang.nif_error({:nif_not_loaded, :allocator_stats})

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:kinda_lua)}/lib/libKindaLuaNIF"
    dylib = "#{nif_file}.dylib"
    if File.exists?(dylib), do: File.ln_s(dylib, "#{nif_file}.so")

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _message}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
