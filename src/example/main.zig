const std = @import("std");
const beam = @import("beam");
const kinda = @import("kinda");
const e = @import("erl_nif");
const capi = @import("prelude.zig");
const root_module = "Elixir.KindaExample.NIF";
const Kinds = struct {
    const CInt = kinda.ResourceKind(c_int, root_module ++ ".CInt");
    const All = .{CInt};
    fn open(env: beam.env) void {
            inline for (All) |k| {
                k.open_all(env);
            }
        }
};

const all_nifs = .{
    kinda.NIFFunc(Kinds.All, capi, "kinda_example_add", .{ .nif_name = "Elixir.KindaExample.NIF.kinda_example_add"}),
} ++ Kinds.CInt.nifs;
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

const entry = e.ErlNifEntry{
    .major = 2,
    .minor = 16,
    .name = root_module,
    .num_of_funcs = all_nifs.len,
    .funcs = &(nifs[0]),
    .load = nif_load,
    .reload = null, // currently unsupported
    .upgrade = null, // currently unsupported
    .unload = null, // currently unsupported
    .vm_variant = "beam.vanilla",
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit),
    .min_erts = "erts-13.0",
};

export fn nif_load(env: beam.env, _: [*c]?*anyopaque, _: beam.term) c_int {
    Kinds.open(env);
    return 0;
}

export fn nif_init() *const e.ErlNifEntry {
    return &entry;
}
