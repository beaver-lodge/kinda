const kinda = @import("kinda");

comptime {
    _ = kinda.DynamicEntryExports(.{
        .name = "Elixir.Kinda.DynamicEntryMissingProvider",
        .load = null,
    });
}
