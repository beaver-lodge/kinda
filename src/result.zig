const beam = @import("beam");
const e = @import("erl_nif");
const std = @import("std");

pub fn nif_with_flags(comptime name: [*c]const u8, comptime arity: usize, comptime f: anytype, comptime flags: u32) type {
    return struct {
        fn exported(env: beam.env, n: c_int, args: [*c]const beam.term) callconv(.C) beam.term {
            if (f(env, n, args)) |r| {
                return r;
            } else |err| {
                return e.enif_raise_exception(env, beam.make_atom(env, @errorName(err)));
            }
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
