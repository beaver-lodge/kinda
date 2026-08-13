const kinda = @import("kinda");

const Resource = struct {};

fn close(_: *Resource, _: bool) void {}

comptime {
    _ = kinda.resourceDestructor(Resource, close);
}
