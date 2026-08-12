const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lua_root = b.option([]const u8, "lua-root", "Lua source root") orelse
        @panic("-Dlua-root is required");

    const lib = b.addLibrary(.{
        .name = "KindaLuaNIF",
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
    lib.root_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/src", .{lua_root}) });
    lib.root_module.addCSourceFile(.{ .file = b.path("native/c-src/kinda_lua_shim.c"), .flags = &.{"-std=c99"} });
    lib.root_module.addCSourceFiles(.{
        .root = .{ .cwd_relative = b.fmt("{s}/src", .{lua_root}) },
        .files = &.{
            "lapi.c", "lauxlib.c", "lbaselib.c", "lcode.c", "lcorolib.c", "lctype.c",
            "ldblib.c", "ldebug.c", "ldo.c", "ldump.c", "lfunc.c", "lgc.c", "linit.c",
            "liolib.c", "llex.c", "lmathlib.c", "lmem.c", "loadlib.c", "lobject.c",
            "lopcodes.c", "loslib.c", "lparser.c", "lstate.c", "lstring.c", "lstrlib.c",
            "ltable.c", "ltablib.c", "ltm.c", "lundump.c", "lutf8lib.c", "lvm.c", "lzio.c",
        },
        .flags = &.{"-std=c99"},
    });
    if (target.result.os.tag == .linux) {
        lib.root_module.addCMacro("LUA_USE_LINUX", "1");
        lib.root_module.linkSystemLibrary("dl", .{});
        lib.root_module.linkSystemLibrary("m", .{});
    } else if (target.result.os.tag == .macos) {
        lib.root_module.addCMacro("LUA_USE_MACOSX", "1");
        lib.root_module.linkSystemLibrary("m", .{});
    }
    lib.linker_allow_shlib_undefined = true;

    const install_nif = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = if (target.result.os.tag == .windows) "libKindaLuaNIF.dll" else null,
    });
    b.getInstallStep().dependOn(&install_nif.step);
}
