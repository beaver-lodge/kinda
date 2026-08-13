const kinda = @import("kinda");

comptime {
    _ = kinda.ResourceRegistry(.{.{ .kind = struct {} }});
}
