const std = @import("std");
const builtin = @import("builtin");
const os = builtin.os.tag;

pub fn build(b: *std.Build) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const lib = b.addSharedLibrary(.{
        .name = "KindaExampleNIF",
        .root_source_file = b.path("native/zig-src/main.zig"),
        .optimize = .Debug,
        .target = b.host,
    });
    const kinda = b.dependencyFromBuildZig(@import("kinda"), .{});
    lib.root_module.addImport("kinda", kinda.module("kinda"));
    lib.root_module.addImport("erl_nif", kinda.module("erl_nif"));
    lib.root_module.addImport("beam", kinda.module("beam"));
    if (os.isDarwin()) {
        lib.root_module.addRPathSpecial("@loader_path");
    } else {
        lib.root_module.addRPathSpecial("$ORIGIN");
    }
    lib.linkSystemLibrary("KindaExample");
    lib.linker_allow_shlib_undefined = true;

    b.installArtifact(lib);
}
