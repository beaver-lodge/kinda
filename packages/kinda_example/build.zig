const std = @import("std");
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
    const os = target.result.os.tag;
    if (os.isDarwin()) {
        lib.root_module.addRPathSpecial("@loader_path");
    } else if (os != .windows) {
        lib.root_module.addRPathSpecial("$ORIGIN");
    }
    lib.root_module.linkSystemLibrary("KindaExample", .{});
    lib.linker_allow_shlib_undefined = true;

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = if (os == .windows) "libKindaExampleNIF.dll" else null,
    });
    b.getInstallStep().dependOn(&install.step);
}
