defmodule KindaExample.NIF do
  dest_dir = Path.join([Mix.Project.app_path(), "native-install"])

  use Kinda.Prebuilt,
    otp_app: :kinda_example,
    lib_name: "kinda_example",
    base_url:
      "https://github.com/beaver-project/beaver-prebuilt/releases/download/2022-10-15-0706",
    version: "0.1.0",
    wrapper: Path.join(File.cwd!(), "native/wrapper.h"),
    zig_src: "native/zig-src",
    zig_proj: "native/zig-proj",
    include_paths: %{
      kinda_example_include: Path.join(File.cwd!(), "native/c-src/include")
    },
    constants: %{
      kinda_example_libdir: Path.join(dest_dir, "lib")
    },
    dest_dir: dest_dir,
    forward_module: KindaExample.Native,
    codegen_module: KindaExample.CodeGen
end
