const std = @import("std");
const kinda = @import("build.imp.zig");
const builtin = @import("builtin");
const os = builtin.os.tag;

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary(kinda.lib_name, "src/main.zig", .unversioned);
    lib.addSystemIncludeDir(kinda.erts_include);
    lib.addSystemIncludeDir(kinda.kinda_example_include);

    lib.addLibPath(kinda.kinda_example_libdir);
    if (os == .linux) {
        lib.addRPath("$ORIGIN");
    }
    if (os == .macos) {
        lib.addRPath("@loader_path");
    }
    lib.linkSystemLibrary("KindaExample");
    lib.linker_allow_shlib_undefined = true;

    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);
}
