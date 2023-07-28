const std = @import("std");
const kinda = @import("build.imp.zig");
const builtin = @import("builtin");
const os = builtin.os.tag;

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target: std.zig.CrossTarget = .{};
    const lib = b.addSharedLibrary(.{
        .name = kinda.lib_name,
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = .ReleaseSafe,
        .target = target,
    });
    lib.addSystemIncludePath(kinda.erts_include);
    lib.addSystemIncludePath(kinda.kinda_example_include);

    lib.addLibraryPath(kinda.kinda_example_libdir);
    if (os == .linux) {
        lib.addRPath("$ORIGIN");
    }
    if (os == .macos) {
        lib.addRPath("@loader_path");
    }
    lib.linkSystemLibrary("KindaExample");
    lib.linker_allow_shlib_undefined = true;

    b.installArtifact(lib);
}
