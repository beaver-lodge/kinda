const kinda = @import("kinda");

comptime {
    _ = kinda.EntryExports(.{
        .nifs = .{},
        .load = null,
    });
}
