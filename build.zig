const std = @import("std");

pub fn build(b: *std.Build) !void {
    const kinda = b.addModule(
        "kinda",
        .{ .root_source_file = b.path("src/kinda.zig") },
    );

    // Get Erlang include directory
    const elixir_cmd = b.addSystemCommand(&.{
        "elixir",
        "--eval",
        ":code.root_dir() |> Path.join(~s[erts-#{:erlang.system_info(:version)}]) |> Path.join(~s[include]) |> dbg |> IO.puts()",
    });
    const erl_include_dir = elixir_cmd.captureStdOut();
    kinda.addIncludePath(erl_include_dir);
}
