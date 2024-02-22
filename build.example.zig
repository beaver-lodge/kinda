const std = @import("std");
const builtin = @import("builtin");
const os = builtin.os.tag;

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target: std.zig.CrossTarget = .{};
    const lib = b.addSharedLibrary(.{
        .name = "KindaExampleNIF",
        .root_source_file = .{ .path = "src/example/main.zig" },
        .optimize = .Debug,
        .target = target,
    });
    const kinda = b.anonymousDependency(".", @import("build.zig"), .{});
    lib.addModule("kinda", kinda.module("kinda"));
    lib.addModule("erl_nif", kinda.module("erl_nif"));
    lib.addModule("beam", kinda.module("beam"));
    if (os.isDarwin()) {
        lib.addRPath(.{ .path = "@loader_path" });
        lib.linkSystemLibrary("KindaExample");
    } else {
        lib.addRPath(.{ .path = ":$ORIGIN" });
        lib.linkSystemLibraryName("KindaExample");
    }
    lib.linker_allow_shlib_undefined = true;

    b.installArtifact(lib);
}
