defmodule KindaExample.NIF do
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

  use Kinda.Prebuilt,
    otp_app: :kinda_example,
    lib_name: "kinda_example",
    base_url:
      "https://github.com/beaver-project/beaver-prebuilt/releases/download/2022-10-15-0706",
    version: "0.1.0",
    dest_dir: "native_install",
    forward_module: KindaExample.Native,
    code_gen_module: KindaExample.CodeGen,
    nifs: [{:kinda_example_add, 2}]
end
