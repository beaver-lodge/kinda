defmodule KindaExample.NIF.Raw do
  use Kinda.CodeGen,
    with: KindaExample.CodeGen,
    root: KindaExample.NIF,
    codec: KindaExample.Native,
    surface: :raw

  for path <-
        Path.wildcard("native/c-src/**/*.h") ++
          Path.wildcard("native/c-src/**/*.cpp") ++
          Path.wildcard("../src/**/*.zig") ++
          ["../build.zig", "../build.example.zig"] do
    @external_resource path
  end

  @on_load :load_nif

  def load_nif do
    nif_file = ~c"#{:code.priv_dir(:kinda_example)}/lib/libKindaExampleNIF"

    if File.exists?(dylib = "#{nif_file}.dylib") do
      File.ln_s(dylib, "#{nif_file}.so")
    end

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} -> IO.puts("Failed to load nif: #{inspect(reason)}")
    end
  end
end

defmodule KindaExample.NIF do
  use Kinda.CodeGen,
    with: KindaExample.CodeGen,
    root: __MODULE__,
    raw_module: __MODULE__.Raw,
    codec: KindaExample.Native,
    surface: :public

  defmodule CInt do
    use Kinda.ResourceKind, raw_module: KindaExample.NIF.Raw, codec: KindaExample.Native
  end

  defmodule StrInt do
    use Kinda.ResourceKind, raw_module: KindaExample.NIF.Raw, codec: KindaExample.Native
  end
end
