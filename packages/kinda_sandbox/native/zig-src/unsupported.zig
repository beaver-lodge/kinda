const kinda = @import("kinda");
const beam = kinda.beam;

pub const Process = struct {};

pub fn spawn(_: beam.env, _: [*c]const beam.term) !Process {
    return error.UnsupportedPlatform;
}

pub fn readEvent(environment: beam.env, _: *Process) beam.term {
    return beam.make_error_atom(environment, "unsupported_platform");
}

pub fn terminate(_: *Process, _: u32) void {}
pub fn destroy(_: beam.env, _: ?*anyopaque) callconv(.c) void {}
