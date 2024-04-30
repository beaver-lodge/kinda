const std = @import("std");

pub fn build(b: *std.Build) !void {
    const erl_nif = b.addModule(
        "erl_nif",
        .{ .root_source_file = .{ .path = "src/erl_nif.zig" } },
    );
    const beam = b.addModule(
        "beam",
        .{ .root_source_file = .{ .path = "src/beam.zig" } },
    );
    beam.addImport("erl_nif", erl_nif);
    const kinda = b.addModule(
        "kinda",
        .{ .root_source_file = .{ .path = "src/kinda.zig" } },
    );
    kinda.addImport("erl_nif", erl_nif);
    kinda.addImport("beam", beam);
}
