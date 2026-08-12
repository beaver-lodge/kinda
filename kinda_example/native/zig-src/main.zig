const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const capi = @import("prelude.zig").c;
const callback_fixture = @import("callback_fixture.zig");
const lifecycle_fixture = @import("lifecycle_fixture.zig");
const public_module = "Elixir.KindaExample.NIF";
const root_module = public_module ++ ".Raw";
const Kinds = struct {
    const CInt = kinda.ResourceKind(c_int, public_module ++ ".CInt");
    const StrInt = kinda.ResourceKind(extern struct {
        i: c_int = 0,
        fn make(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            var s: beam.binary = try beam.get_binary(env, args[0]);
            const integer = try std.fmt.parseInt(i32, s.data[0..s.size], 10);
            return CInt.resource.make(env, integer) catch return beam.Error.@"Fail to make resource";
        }
        pub const maker = .{ make, 1 };
    }, public_module ++ ".StrInt");
    const All = .{ CInt, StrInt };
    fn open(env: beam.env) void {
        inline for (All) |k| {
            k.open_all(env);
        }
    }
};

const all_nifs = .{
    kinda.NIFFunc(Kinds.All, capi, "kinda_example_add", .{}),
} ++ Kinds.CInt.nifs ++ Kinds.StrInt.nifs ++ callback_fixture.nifs ++ lifecycle_fixture.nifs;
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

const entry = e.ErlNifEntry{
    .major = 2,
    .minor = 16,
    .name = root_module,
    .num_of_funcs = nifs.len,
    .funcs = &(nifs[0]),
    .load = nif_load,
    .reload = null,
    .upgrade = nif_upgrade,
    .unload = nif_unload,
    .vm_variant = "beam.vanilla",
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit),
    .min_erts = "erts-13.0",
};

export fn nif_load(env: beam.env, _: [*c]?*anyopaque, _: beam.term) c_int {
    Kinds.open(env);
    kinda.callback_runtime.ReplyToken.open(env);
    callback_fixture.open(env);
    lifecycle_fixture.open(env);
    return 0;
}

export fn nif_upgrade(
    env: beam.env,
    priv_data: [*c]?*anyopaque,
    _: [*c]?*anyopaque,
    load_info: beam.term,
) c_int {
    return nif_load(env, priv_data, load_info);
}

export fn nif_unload(_: beam.env, _: ?*anyopaque) void {}

export fn nif_init() *const e.ErlNifEntry {
    return &entry;
}
