const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "KindaSandboxNIF",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig-src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const kinda = b.dependencyFromBuildZig(@import("kinda"), .{});
    lib.root_module.addImport("kinda", kinda.module("kinda"));
    lib.linker_allow_shlib_undefined = true;

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = if (target.result.os.tag == .windows) "libKindaSandboxNIF.dll" else null,
    });
    b.getInstallStep().dependOn(&install.step);
}
