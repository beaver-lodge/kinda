const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const nifApi = kinda.nifApi;
const result = kinda.result;

var pointer_type: beam.resource_type = undefined;
var list_array_type: beam.resource_type = undefined;
var binary_array_type: beam.resource_type = undefined;

var values_destroyed: std.atomic.Value(usize) = .init(0);
var pointers_destroyed: std.atomic.Value(usize) = .init(0);
var list_arrays_destroyed: std.atomic.Value(usize) = .init(0);
var binary_arrays_destroyed: std.atomic.Value(usize) = .init(0);

const Value = extern struct {
    value: c_int,

    pub fn destroy(_: beam.env, _: ?*anyopaque) callconv(.c) void {
        _ = values_destroyed.fetchAdd(1, .monotonic);
    }
};
const ValueKind = kinda.ResourceKind(Value, "Elixir.KindaExample.NIF.LifecycleFixture.Value");

fn destroyPointer(_: beam.env, _: ?*anyopaque) callconv(.c) void {
    _ = pointers_destroyed.fetchAdd(1, .monotonic);
}

fn destroyListArray(_: beam.env, _: ?*anyopaque) callconv(.c) void {
    _ = list_arrays_destroyed.fetchAdd(1, .monotonic);
}

fn destroyBinaryArray(_: beam.env, _: ?*anyopaque) callconv(.c) void {
    _ = binary_arrays_destroyed.fetchAdd(1, .monotonic);
}

fn makeValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return ValueKind.resource.make(environment, .{
        .value = try beam.get_c_int(environment, args[0]),
    });
}

fn makePointer(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return beam.get_resource_ptr_from_term(
        environment,
        [*c]Value,
        ValueKind.resource.t,
        pointer_type,
        args[0],
    );
}

fn makeListArray(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return beam.get_resource_array_from_list(
        c_int,
        environment,
        ValueKind.resource.t,
        list_array_type,
        args[0],
    );
}

fn makeBinaryArray(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return beam.get_resource_array_from_binary(environment, binary_array_type, args[0]);
}

fn stats(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    var terms = [_]beam.term{
        beam.make_usize(environment, values_destroyed.load(.monotonic)),
        beam.make_usize(environment, pointers_destroyed.load(.monotonic)),
        beam.make_usize(environment, list_arrays_destroyed.load(.monotonic)),
        beam.make_usize(environment, binary_arrays_destroyed.load(.monotonic)),
    };
    return beam.make_tuple(environment, &terms);
}

pub fn open(environment: beam.env) void {
    ValueKind.open(environment);
    pointer_type = nifApi("enif_open_resource_type")(
        environment,
        null,
        "Kinda.LifecycleFixture.Pointer",
        destroyPointer,
        e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER,
        null,
    );
    list_array_type = nifApi("enif_open_resource_type")(
        environment,
        null,
        "Kinda.LifecycleFixture.ListArray",
        destroyListArray,
        e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER,
        null,
    );
    binary_array_type = nifApi("enif_open_resource_type")(
        environment,
        null,
        "Kinda.LifecycleFixture.BinaryArray",
        destroyBinaryArray,
        e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER,
        null,
    );

    if (ValueKind.resource.t == null or pointer_type == null or list_array_type == null or binary_array_type == null)
        @panic("failed to open lifecycle fixture resource types");
}

pub const nifs = .{
    result.nif("lifecycle_fixture_make_value", 1, makeValue).entry,
    result.nif("lifecycle_fixture_make_pointer", 1, makePointer).entry,
    result.nif("lifecycle_fixture_make_list_array", 1, makeListArray).entry,
    result.nif("lifecycle_fixture_make_binary_array", 1, makeBinaryArray).entry,
    result.nif("lifecycle_fixture_stats", 0, stats).entry,
};
