const kinda = @import("kinda");

const Resource = struct {};

fn destroy(_: *Resource) void {}

comptime {
    _ = kinda.RawResourceType(Resource, "Kinda.InvalidRawResource", destroy);
}
