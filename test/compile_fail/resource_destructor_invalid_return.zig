const kinda = @import("kinda");

const Resource = struct {};

fn close(_: *Resource) bool {
    return true;
}

comptime {
    _ = kinda.resourceDestructor(Resource, close);
}
