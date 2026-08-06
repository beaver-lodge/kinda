//! Reusable projection helpers for consumer-defined callback signatures.
//!
//! Kinda owns BEAM-safe transport and the common shapes below. Consumers keep
//! their native ABI trampoline and resource validation close to the C API.

const std = @import("std");
const beam = @import("beam.zig");
const callback_runtime = @import("callback_runtime.zig");

/// Projects one handle-like value through a consumer ResourceKind.
pub fn handle(comptime Kind: type, environment: beam.env, value: Kind.T) !beam.term {
    return Kind.resource.make_kind(environment, value);
}

/// Projects a native range of handle-like values into a BEAM list. The list
/// owns resource terms, not the native range storage.
pub fn handleRange(
    comptime Kind: type,
    environment: beam.env,
    values: []const Kind.T,
) !beam.term {
    const terms = try beam.allocator.alloc(beam.term, values.len);
    defer beam.allocator.free(terms);

    for (values, 0..) |value, index| {
        terms[index] = try handle(Kind, environment, value);
    }
    return beam.make_term_list(environment, terms);
}

/// Reads a scalar callback result from the transport code.
pub fn scalarResult(
    comptime T: type,
    response: callback_runtime.Response,
    failure: T,
) T {
    if (!response.success) return failure;
    return std.math.cast(T, response.code) orelse failure;
}

/// Reads an enum callback result from the transport code.
pub fn enumResult(
    comptime T: type,
    response: callback_runtime.Response,
    failure: T,
) T {
    if (!response.success) return failure;
    return switch (@typeInfo(T)) {
        .@"enum" => std.enums.fromInt(T, response.code) orelse failure,
        .int => std.math.cast(T, response.code) orelse failure,
        else => failure,
    };
}

/// Returns consumer-projected data only after a successful reply.
pub fn projection(response: callback_runtime.Response) ?usize {
    return if (response.success) response.projection else null;
}
