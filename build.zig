const std = @import("std");

pub fn build(b: *std.Build) !void {
    const kinda = b.addModule(
        "kinda",
        .{ .root_source_file = b.path("src/kinda.zig") },
    );
    // For ZLS integration, add the ERTS include path if not building with elixir_make
    if (b.graph.environ_map.get("ERTS_INCLUDE_DIR") == null) {
        const argv = [_][]const u8{
            "erl",
            "-eval",
            "io:format(\"~s\", [lists:concat([code:root_dir(), \"/erts-\", erlang:system_info(version), \"/include\"])])",
            "-s",
            "init",
            "stop",
            "-noshell",
        };
        const erlang_include_path = b.run(&argv);
        kinda.addIncludePath(.{ .cwd_relative = erlang_include_path });
    }
}
