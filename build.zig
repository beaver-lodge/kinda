const std = @import("std");

pub fn build(b: *std.Build) !void {
    _ = b.addModule(
        "kinda",
        .{ .root_source_file = b.path("src/kinda.zig") },
    );
}
