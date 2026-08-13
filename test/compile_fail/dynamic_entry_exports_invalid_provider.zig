const kinda = @import("kinda");

fn provideNifs() void {}

comptime {
    _ = kinda.DynamicEntryExports(.{
        .name = "Elixir.Kinda.DynamicEntryInvalidProvider",
        .nifs_provider = provideNifs,
        .load = null,
    });
}
