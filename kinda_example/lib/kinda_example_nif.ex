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

  for {name, arity} <- [
        callback_fixture_register: 3,
        callback_fixture_invoke_on_scheduler: 2,
        callback_fixture_invoke_on_worker: 2,
        callback_fixture_destroy_on_worker: 1,
        callback_fixture_stats: 0,
        callback_fixture_reply_code: 3,
        callback_fixture_reply_projection: 4,
        callback_fixture_cancel: 1,
        lifecycle_fixture_make_value: 1,
        lifecycle_fixture_make_pointer: 1,
        lifecycle_fixture_make_list_array: 1,
        lifecycle_fixture_make_binary_array: 1,
        lifecycle_fixture_stats: 0
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)

    def unquote(name)(unquote_splicing(args)),
      do: :erlang.nif_error({:nif_not_loaded, unquote(name)})
  end

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

  defmodule CallbackHandle do
    defstruct [:ref]

    @type t() :: %__MODULE__{ref: reference()}
  end
end
