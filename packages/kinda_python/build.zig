const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const python_include = b.option([]const u8, "python-include", "CPython include directory") orelse
        @panic("-Dpython-include is required");
    const python_library_path = b.option([]const u8, "python-library-path", "CPython library path") orelse
        @panic("-Dpython-library-path is required");

    const lib = b.addLibrary(.{
        .name = "KindaPythonNIF",
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
    lib.root_module.addIncludePath(.{ .cwd_relative = python_include });
    const framework_marker = ".framework/";
    const framework_index = std.mem.indexOf(u8, python_library_path, framework_marker);
    if (target.result.os.tag == .macos and framework_index != null) {
        const bundle_end = framework_index.? + ".framework".len;
        const bundle = python_library_path[0..bundle_end];
        const bundle_name = std.fs.path.basename(bundle);
        const framework_name = bundle_name[0 .. bundle_name.len - ".framework".len];
        lib.root_module.addFrameworkPath(.{ .cwd_relative = std.fs.path.dirname(bundle) orelse "." });
        lib.root_module.linkFramework(framework_name, .{});
    } else {
        lib.root_module.addObjectFile(.{ .cwd_relative = python_library_path });
    }

    if (target.result.os.tag != .windows and framework_index == null) {
        lib.root_module.addRPath(.{ .cwd_relative = std.fs.path.dirname(python_library_path) orelse "." });
    }

    lib.linker_allow_shlib_undefined = true;

    const install_nif = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = if (target.result.os.tag == .windows) "libKindaPythonNIF.dll" else null,
    });
    b.getInstallStep().dependOn(&install_nif.step);
}
