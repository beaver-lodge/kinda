const std = @import("std");
const kinda = @import("kinda");

const Parent = struct {
    children: std.atomic.Value(usize) = .init(0),
    close_requested: std.atomic.Value(bool) = .init(false),

    fn close(_: *Parent) void {}
    fn closeIfUnused(_: *Parent) void {}
};

comptime {
    kinda.validateDeferredCloseParent(Parent, .{
        .counter = "children",
        .close = Parent.close,
        .close_if_unused = Parent.closeIfUnused,
    });
}
