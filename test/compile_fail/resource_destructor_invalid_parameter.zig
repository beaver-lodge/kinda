const kinda = @import("kinda");

const Resource = struct {};
const Other = struct {};

fn close(_: *Other) void {}

comptime {
    _ = kinda.resourceDestructor(Resource, close);
}
