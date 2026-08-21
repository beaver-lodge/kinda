defmodule Kinda.Sandbox.Native do
  @moduledoc false

  use Kinda.CodeGen,
    with: Kinda.Sandbox.Native.CodeGen,
    root: __MODULE__,
    codec: __MODULE__.Codec,
    surface: :raw

  @on_load :load_nif

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:kinda_sandbox)}/lib/libKindaSandboxNIF"
    dylib = "#{nif_file}.dylib"

    if File.exists?(dylib) and not File.exists?("#{nif_file}.so") do
      File.ln_s(dylib, "#{nif_file}.so")
    end

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} -> raise Kinda.NIFLoadError, path: nif_file, reason: reason
    end
  end

  defmodule Codec do
    @moduledoc false
    def normalize(value), do: value
  end
end
