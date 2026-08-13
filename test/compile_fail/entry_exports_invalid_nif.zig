const kinda = @import("kinda");

comptime {
    _ = kinda.EntryExports(.{
        .name = "contract_fixture",
        .nifs = .{1},
        .load = null,
    });
}
