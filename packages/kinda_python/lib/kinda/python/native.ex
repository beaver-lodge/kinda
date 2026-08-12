defmodule Kinda.Python.Native do
  @moduledoc false

  @on_load :load_nif

  def version, do: :erlang.nif_error({:nif_not_loaded, :version})
  def initialized?, do: :erlang.nif_error({:nif_not_loaded, :initialized?})
  def free_threaded_build?, do: :erlang.nif_error({:nif_not_loaded, :free_threaded_build?})
  def create_interpreter, do: :erlang.nif_error({:nif_not_loaded, :create_interpreter})

  def close_interpreter(_interpreter),
    do: :erlang.nif_error({:nif_not_loaded, :close_interpreter})

  def eval(_interpreter, _code), do: :erlang.nif_error({:nif_not_loaded, :eval})
  def close_value(_value), do: :erlang.nif_error({:nif_not_loaded, :close_value})
  def value_to_term(_value), do: :erlang.nif_error({:nif_not_loaded, :value_to_term})

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:kinda_python)}/lib/libKindaPythonNIF"
    dylib = "#{nif_file}.dylib"

    if File.exists?(dylib) do
      File.ln_s(dylib, "#{nif_file}.so")
    end

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _message}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
