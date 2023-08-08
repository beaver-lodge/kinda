const std = @import("std");

fn add_mod(b: *std.Build, name: []const u8, path: []const u8) void {
    const lib_mod = b.addModule(
        name,
        .{ .source_file = .{ .path = path } },
    );
    _ = lib_mod;
}

pub fn build(b: *std.Build) !void {
    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const optimize: std.builtin.OptimizeMode = .Debug;
    _ = optimize;

    const erl_nif = b.addModule(
        "erl_nif",
        .{ .source_file = .{ .path = "src/erl_nif.zig" } },
    );
    const beam = b.addModule(
        "beam",
        .{ .source_file = .{ .path = "src/beam.zig" } },
    );
    try beam.dependencies.put("erl_nif", erl_nif);
    const kinda = b.addModule(
        "kinda",
        .{ .source_file = .{ .path = "src/kinda.zig" } },
    );
    try kinda.dependencies.put("erl_nif", erl_nif);
    try kinda.dependencies.put("beam", beam);
}
