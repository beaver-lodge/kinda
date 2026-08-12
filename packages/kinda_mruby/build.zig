const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mruby_root = b.option([]const u8, "mruby-root", "Built mruby root") orelse
        @panic("-Dmruby-root is required");
    const mruby_shim_object = b.option([]const u8, "mruby-shim-object", "Precompiled mruby shim object");

    const lib = b.addLibrary(.{
        .name = "KindaMRubyNIF",
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
    lib.root_module.addCMacro("MRB_NO_DEFAULT_RO_DATA_P", "1");
    lib.root_module.addCMacro("MRB_WORD_BOXING", "1");
    lib.root_module.addCMacro("MRB_INT64", "1");
    lib.root_module.addIncludePath(b.path("native/include"));
    lib.root_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{mruby_root}) });
    lib.root_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/build/host/include", .{mruby_root}) });
    if (mruby_shim_object) |object| {
        lib.root_module.addObjectFile(.{ .cwd_relative = object });
    } else {
        lib.root_module.addCSourceFile(.{
            .file = b.path("native/c-src/kinda_mruby_shim.c"),
            .flags = &.{"-std=c99"},
        });
    }
    const archive = if (target.result.os.tag == .windows) "libmruby.lib" else "libmruby.a";
    lib.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/build/host/lib/{s}", .{ mruby_root, archive }) });
    if (target.result.os.tag == .windows) {
        lib.root_module.linkSystemLibrary("ws2_32", .{});
    } else {
        lib.root_module.linkSystemLibrary("m", .{});
        lib.linker_allow_shlib_undefined = true;
    }

    const install_nif = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = if (target.result.os.tag == .windows) "libKindaMRubyNIF.dll" else null,
    });
    b.getInstallStep().dependOn(&install_nif.step);
}
