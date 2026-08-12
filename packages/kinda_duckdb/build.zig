const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "KindaDuckDBNIF",
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
    lib.root_module.addIncludePath(b.path(".runtime/current/include"));
    lib.root_module.addLibraryPath(b.path(".runtime/current/lib"));
    lib.root_module.linkSystemLibrary("duckdb", .{});

    const runtime_name = switch (target.result.os.tag) {
        .macos => "libduckdb.dylib",
        .windows => "duckdb.dll",
        else => "libduckdb.so",
    };
    const runtime_path = b.fmt(".runtime/current/lib/{s}", .{runtime_name});
    const runtime_install_path = b.fmt("lib/{s}", .{runtime_name});

    if (target.result.os.tag == .macos) {
        lib.root_module.addRPathSpecial("@loader_path");
    } else if (target.result.os.tag != .windows) {
        lib.root_module.addRPathSpecial("$ORIGIN");
    }

    lib.linker_allow_shlib_undefined = true;

    const install_nif = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = if (target.result.os.tag == .windows) "libKindaDuckDBNIF.dll" else null,
    });
    b.getInstallStep().dependOn(&install_nif.step);

    const runtime = b.addInstallFile(
        b.path(runtime_path),
        runtime_install_path,
    );
    b.getInstallStep().dependOn(&runtime.step);

    if (target.result.os.tag == .windows) {
        const loader = b.addLibrary(.{
            .name = "KindaDuckDBLoaderNIF",
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .root_source_file = b.path("native/zig-src/windows_loader.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        loader.root_module.addImport("kinda", kinda.module("kinda"));

        const install_loader = b.addInstallArtifact(loader, .{
            .dest_dir = .{ .override = .lib },
            .dest_sub_path = "libKindaDuckDBLoaderNIF.dll",
        });
        b.getInstallStep().dependOn(&install_loader.step);
    }
}
