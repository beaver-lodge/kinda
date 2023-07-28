const std = @import("std");
const beam = @import("beam.zig");
const kinda = @import("kinda.zig");
const e = @import("erl_nif.zig");
const capi = @import("kinda_example.imp.zig");

export fn add(a: i32, b: i32) i32 {
    return a + b;
}
pub export const num_nifs = capi.generated_nifs.len;
pub export var nifs: [num_nifs]e.ErlNifFunc = capi.generated_nifs;

const entry = e.ErlNifEntry{
    .major = 2,
    .minor = 16,
    .name = capi.root_module,
    .num_of_funcs = num_nifs,
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
    kinda.open_internal_resource_types(env);
    capi.open_generated_resource_types(env);
    return 0;
}

export fn nif_init() *const e.ErlNifEntry {
    return &entry;
}
