const kinda = @import("kinda");

comptime {
    _ = kinda.ResourceRegistry(.{
        kinda.ResourceRegistration{ .kind = struct {} },
    });
}
