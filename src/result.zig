const beam = @import("beam.zig");
const kinda = @import("kinda.zig");
const e = kinda.erl_nif;
const nifApi = kinda.nifApi;
const std = @import("std");

pub fn is_stack_trace_enabled() bool {
    var value: [256]u8 = undefined;
    var value_size: usize = value.len;
    return nifApi("enif_getenv")("KINDA_DUMP_STACK_TRACE", &value[0], &value_size) == 0;
}

pub fn nif_with_flags(comptime name: [*c]const u8, comptime arity: usize, comptime f: anytype, comptime flags: u32) type {
    validate_nif_function(f);

    return struct {
        fn exported(env: beam.env, n: c_int, args: [*c]const beam.term) callconv(.c) beam.term {
            return f(env, n, args) catch |err| {
                if (is_stack_trace_enabled()) {
                    std.debug.dumpErrorReturnTrace(@errorReturnTrace().?);
                }
                return beam.raise_call_error(env, .{
                    .message = @errorName(err),
                    .reason = "native_error",
                    .phase = "native",
                    .function = std.mem.span(name),
                    .arity = arity,
                    .native_error = err,
                });
            };
        }
        pub const entry = e.ErlNifFunc{ .name = name, .arity = arity, .fptr = exported, .flags = flags };
    };
}

fn validate_nif_function(comptime f: anytype) void {
    const function_info = switch (@typeInfo(@TypeOf(f))) {
        .@"fn" => |info| info,
        else => @compileError("Kinda.result.nif expects a function"),
    };

    if (function_info.params.len != 3 or
        function_info.params[0].type != beam.env or
        function_info.params[1].type != c_int or
        function_info.params[2].type != [*c]const beam.term)
    {
        @compileError("Kinda.result.nif function must accept (beam.env, c_int, [*c]const beam.term)");
    }

    const Return = function_info.return_type orelse
        @compileError("Kinda.result.nif function must return an error union containing beam.term");

    switch (@typeInfo(Return)) {
        .error_union => |error_union| {
            if (error_union.payload != beam.term) {
                @compileError("Kinda.result.nif function must return an error union containing beam.term");
            }
        },
        else => @compileError("Kinda.result.nif function must return an error union containing beam.term"),
    }
}

pub fn nif(comptime name: [*c]const u8, comptime arity: usize, comptime f: anytype) type {
    return nif_with_flags(name, arity, f, 0);
}

pub fn wrap(comptime f: anytype) fn (env: beam.env, n: c_int, args: [*c]const beam.term) callconv(.C) beam.term {
    return nif("", 0, f).exported;
}
