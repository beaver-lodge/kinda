defmodule KindaExample.NIF do
  dest_dir = Path.join([Mix.Project.app_path(), "native_install"])

  for path <-
        Path.wildcard("native/c-src/**/*.h") ++
          Path.wildcard("native/c-src/**/*.cpp") ++
          Path.wildcard("native/mlir-zig-src/**/*.zig") ++
          ["native/zig-proj/#{Mix.env()}/build.zig"] do
    @external_resource path
  end

  use Kinda.Prebuilt,
    otp_app: :kinda_example,
    lib_name: "kinda_example",
    base_url:
      "https://github.com/beaver-project/beaver-prebuilt/releases/download/2022-10-15-0706",
    version: "0.1.0",
    wrapper: Path.join(File.cwd!(), "native/c-src/include/wrapper.h"),
    zig_src: "native/zig-src",
    zig_proj: "native/zig-proj",
    translate_args: ["-I", Path.join(File.cwd!(), "native/c-src/include")],
    build_args:
      Enum.flat_map([dest_dir, Path.join(File.cwd!(), "native/c-src")], &["--search-prefix", &1]),
    dest_dir: dest_dir,
    forward_module: KindaExample.Native,
    code_gen_module: KindaExample.CodeGen
end
