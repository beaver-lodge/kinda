defmodule Kinda.Python.Native do
  @moduledoc false

  @on_load :load_nif

  def version, do: :erlang.nif_error({:nif_not_loaded, :version})
  def initialized?, do: :erlang.nif_error({:nif_not_loaded, :initialized?})
  def free_threaded_build?, do: :erlang.nif_error({:nif_not_loaded, :free_threaded_build?})

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
