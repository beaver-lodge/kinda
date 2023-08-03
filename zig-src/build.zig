const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const optimize: std.builtin.OptimizeMode = .Debug;
    _ = optimize;

    const shared = b.createModule(.{
        .source_file = .{ .path = "shared.zig" },
    });
    _ = shared;
}
