const std = @import("std");
const builtin = @import("builtin");
const os = builtin.os.tag;

pub fn build(b: *std.Build) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "KindaExampleNIF",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig-src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const kinda = b.dependencyFromBuildZig(@import("kinda"), .{});
    lib.root_module.addImport("kinda", kinda.module("kinda"));
    if (os.isDarwin()) {
        lib.root_module.addRPathSpecial("@loader_path");
    } else {
        lib.root_module.addRPathSpecial("$ORIGIN");
    }
    lib.linkSystemLibrary("KindaExample");
    lib.linker_allow_shlib_undefined = true;

    b.installArtifact(lib);
}
