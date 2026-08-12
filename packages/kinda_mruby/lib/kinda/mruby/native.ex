defmodule Kinda.MRuby.Native do
  @moduledoc false
  @on_load :load_nif

  def version, do: :erlang.nif_error({:nif_not_loaded, :version})
  def eval(_code), do: :erlang.nif_error({:nif_not_loaded, :eval})
  def create_vm, do: :erlang.nif_error({:nif_not_loaded, :create_vm})
  def close_vm(_vm), do: :erlang.nif_error({:nif_not_loaded, :close_vm})
  def eval_value(_vm, _code), do: :erlang.nif_error({:nif_not_loaded, :eval_value})
  def close_value(_value), do: :erlang.nif_error({:nif_not_loaded, :close_value})
  def value_to_term(_value), do: :erlang.nif_error({:nif_not_loaded, :value_to_term})
  def compile_bytecode(_code), do: :erlang.nif_error({:nif_not_loaded, :compile_bytecode})
  def close_bytecode(_bytecode), do: :erlang.nif_error({:nif_not_loaded, :close_bytecode})
  def run_bytecode(_vm, _bytecode), do: :erlang.nif_error({:nif_not_loaded, :run_bytecode})

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:kinda_mruby)}/lib/libKindaMRubyNIF"
    dylib = "#{nif_file}.dylib"
    if File.exists?(dylib), do: File.ln_s(dylib, "#{nif_file}.so")

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _message}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
