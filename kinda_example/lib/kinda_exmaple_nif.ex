defmodule KindaExample.NIF do
  @nifs use Kinda.CodeGen,
          with: KindaExample.CodeGen,
          root: __MODULE__,
          forward: KindaExample.Native
  defmodule CInt do
    use Kinda.ResourceKind,
      forward_module: KindaExample.Native
  end

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
