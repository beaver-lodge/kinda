const std = @import("std");
const builtin = @import("builtin");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;
const lua = @cImport({ @cInclude("kinda_lua_shim.h"); });

const root_module = "Elixir.Kinda.Lua.Native";
const cpu_bound: u32 = 1;
const Error = error{ FailedToEvaluate, UnsupportedValue };

fn eval(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const code = try beam.get_char_slice(environment, args[0]);
    var value: lua.struct_kinda_lua_result = std.mem.zeroes(lua.struct_kinda_lua_result);
    if (lua.kinda_lua_eval(code.ptr, code.len, &value) != 0) return Error.FailedToEvaluate;
    defer lua.kinda_lua_result_release(&value);
    return switch (value.type) {
        lua.KINDA_LUA_NIL => beam.make_nil(environment),
        lua.KINDA_LUA_BOOLEAN => beam.make_bool(environment, value.boolean_value != 0),
        lua.KINDA_LUA_INTEGER => beam.make_i64(environment, value.integer_value),
        lua.KINDA_LUA_NUMBER => beam.make_f64(environment, value.number_value),
        lua.KINDA_LUA_STRING => beam.make_slice(environment, value.string_value[0..value.string_length]),
        else => Error.UnsupportedValue,
    };
}

fn version(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_slice(environment, std.mem.span(lua.kinda_lua_version()));
}

const all_nifs = .{
    result.nif("version", 0, version).entry,
    result.nif_with_flags("eval", 1, eval, cpu_bound).entry,
};
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

const entry = e.ErlNifEntry{ .major = 2, .minor = 16, .name = root_module, .num_of_funcs = nifs.len, .funcs = &(nifs[0]), .load = null, .reload = null, .upgrade = null, .unload = null, .vm_variant = "beam.vanilla", .options = 1, .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit), .min_erts = "erts-15.0" };

const NifInit = if (builtin.os.tag == .windows) struct {
    var callbacks: e.TWinDynNifCallbacks = undefined;
    fn init(win_callbacks: *const e.TWinDynNifCallbacks) callconv(.c) *const e.ErlNifEntry { callbacks = win_callbacks.*; return &entry; }
    fn exportSymbols() void { @export(&callbacks, .{ .name = "WinDynNifCallbacks" }); @export(&init, .{ .name = "nif_init" }); }
} else struct {
    fn init() callconv(.c) *const e.ErlNifEntry { return &entry; }
    fn exportSymbols() void { @export(&init, .{ .name = "nif_init" }); }
};
comptime { NifInit.exportSymbols(); }
