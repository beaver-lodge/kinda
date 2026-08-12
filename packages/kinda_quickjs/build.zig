const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const quickjs_root = b.option([]const u8, "quickjs-root", "QuickJS source root") orelse
        @panic("-Dquickjs-root is required");

    const lib = b.addLibrary(.{
        .name = "KindaQuickJSNIF",
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
    lib.root_module.addIncludePath(b.path("native/include"));
    lib.root_module.addIncludePath(.{ .cwd_relative = quickjs_root });
    lib.root_module.addCMacro("CONFIG_VERSION", "\"2026-06-04\"");
    lib.root_module.addCMacro("_GNU_SOURCE", "1");
    lib.root_module.addCSourceFile(.{ .file = b.path("native/c-src/kinda_quickjs_shim.c"), .flags = &.{"-std=c11"} });
    lib.root_module.addCSourceFiles(.{
        .root = .{ .cwd_relative = quickjs_root },
        .files = &.{ "quickjs.c", "dtoa.c", "libregexp.c", "libunicode.c", "cutils.c" },
        .flags = &.{ "-std=gnu11", "-Wno-discarded-qualifiers" },
    });
    if (target.result.os.tag != .windows) lib.root_module.linkSystemLibrary("m", .{});
    lib.linker_allow_shlib_undefined = true;

    const install_nif = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = if (target.result.os.tag == .windows) "libKindaQuickJSNIF.dll" else null,
    });
    b.getInstallStep().dependOn(&install_nif.step);
}
