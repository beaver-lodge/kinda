const beam = @import("beam");
const e = @import("erl_nif");
const std = @import("std");

pub fn nif_with_flags(comptime name: [*c]const u8, comptime arity: usize, comptime f: anytype, comptime flags: u32) type {
    const ns = "Elixir.";
    return struct {
        fn exported(env: beam.env, n: c_int, args: [*c]const beam.term) callconv(.C) beam.term {
            return f(env, n, args) catch |err| {
                const ert = @errorReturnTrace();
                return beam.raise_exception(env, ns ++ "Kinda.CallError", err, ert);
            };
        }
        pub const entry = e.ErlNifFunc{ .name = name, .arity = arity, .fptr = exported, .flags = flags };
    };
}

pub fn nif(comptime name: [*c]const u8, comptime arity: usize, comptime f: anytype) type {
    return nif_with_flags(name, arity, f, 0);
}

pub fn wrap(comptime f: anytype) fn (env: beam.env, n: c_int, args: [*c]const beam.term) callconv(.C) beam.term {
    return nif("", 0, f).exported;
}
