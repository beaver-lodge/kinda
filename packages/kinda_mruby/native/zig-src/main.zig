const builtin = @import("builtin");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;
const mrb = @cImport({
    @cInclude("kinda_mruby_shim.h");
});

const root_module = "Elixir.Kinda.MRuby.Native";
const cpu_bound: u32 = 1;
const Error = error{ FailedToCreateVM, FailedToEvaluate, UnsupportedValue };

fn eval(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const code = try beam.get_char_slice(environment, args[0]);
    const state = mrb.kinda_mruby_open() orelse return Error.FailedToCreateVM;
    defer mrb.kinda_mruby_close(state);
    var raised: c_int = 0;
    const value = mrb.kinda_mruby_eval(state, code.ptr, code.len, &raised);
    if (raised != 0 or mrb.kinda_mruby_raised(state) != 0) return Error.FailedToEvaluate;

    return switch (mrb.kinda_mruby_type(value)) {
        mrb.KINDA_MRUBY_TT_FALSE => if (mrb.kinda_mruby_nil(value) != 0) beam.make_nil(environment) else beam.make_bool(environment, false),
        mrb.KINDA_MRUBY_TT_TRUE => beam.make_bool(environment, true),
        mrb.KINDA_MRUBY_TT_INTEGER => beam.make_i64(environment, mrb.kinda_mruby_integer(value)),
        mrb.KINDA_MRUBY_TT_STRING => beam.make_slice(environment, mrb.kinda_mruby_string_ptr(value)[0..mrb.kinda_mruby_string_len(value)]),
        else => Error.UnsupportedValue,
    };
}

fn version(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_slice(environment, std.mem.span(mrb.kinda_mruby_version()));
}

const std = @import("std");
const all_nifs = .{
    result.nif("version", 0, version).entry,
    result.nif_with_flags("eval", 1, eval, cpu_bound).entry,
};
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

const entry = e.ErlNifEntry{ .major = 2, .minor = 16, .name = root_module, .num_of_funcs = nifs.len, .funcs = &(nifs[0]), .load = null, .reload = null, .upgrade = null, .unload = null, .vm_variant = "beam.vanilla", .options = 1, .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit), .min_erts = "erts-15.0" };

const NifInit = if (builtin.os.tag == .windows) struct {
    var callbacks: e.TWinDynNifCallbacks = undefined;
    fn init(win_callbacks: *const e.TWinDynNifCallbacks) callconv(.c) *const e.ErlNifEntry {
        callbacks = win_callbacks.*;
        return &entry;
    }
    fn exportSymbols() void {
        @export(&callbacks, .{ .name = "WinDynNifCallbacks" });
        @export(&init, .{ .name = "nif_init" });
    }
} else struct {
    fn init() callconv(.c) *const e.ErlNifEntry {
        return &entry;
    }
    fn exportSymbols() void {
        @export(&init, .{ .name = "nif_init" });
    }
};
comptime {
    NifInit.exportSymbols();
}
