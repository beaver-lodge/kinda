const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite = b.addLibrary(.{
        .name = "KindaSQLite",
        .linkage = if (target.result.os.tag == .windows) .static else .dynamic,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    sqlite.root_module.addIncludePath(b.path("vendor/sqlite"));
    sqlite.root_module.addCSourceFile(.{
        .file = b.path("vendor/sqlite/sqlite3.c"),
        .flags = &.{
            "-std=c99",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_OMIT_LOAD_EXTENSION",
        },
    });
    sqlite.root_module.addCSourceFile(.{
        .file = b.path("native/c-src/sqlite_bridge.c"),
        .flags = &.{"-std=c99"},
    });

    const lib = b.addLibrary(.{
        .name = "KindaSQLiteNIF",
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
    lib.root_module.addIncludePath(b.path("vendor/sqlite"));
    lib.root_module.addIncludePath(b.path("native/c-src"));
    lib.root_module.linkLibrary(sqlite);
    if (target.result.os.tag == .macos) {
        lib.root_module.addRPathSpecial("@loader_path");
    } else if (target.result.os.tag != .windows) {
        lib.root_module.addRPathSpecial("$ORIGIN");
    }
    lib.linker_allow_shlib_undefined = true;

    const install_sqlite = b.addInstallArtifact(sqlite, .{
        .dest_dir = .{ .override = .lib },
    });
    const install_nif = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = if (target.result.os.tag == .windows) "libKindaSQLiteNIF.dll" else null,
    });
    b.getInstallStep().dependOn(&install_sqlite.step);
    b.getInstallStep().dependOn(&install_nif.step);
}
