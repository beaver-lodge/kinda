const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;
const windows = @cImport({
    @cInclude("windows.h");
});

const root_module = "Elixir.Kinda.DuckDB.WindowsLoader";

const Error = error{FailedToLoadLibrary};

fn loadLibrary(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const path = try beam.get_char_slice(environment, args[0]);
    const wide_path = try std.unicode.utf8ToUtf16LeAllocZ(beam.allocator, path);
    defer beam.allocator.free(wide_path);

    if (windows.GetModuleHandleW(wide_path.ptr) == null and
        windows.LoadLibraryW(wide_path.ptr) == null) return Error.FailedToLoadLibrary;
    return beam.make_atom(environment, "ok");
}

const all_nifs = .{result.nif("load_library", 1, loadLibrary).entry};
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

const entry = e.ErlNifEntry{
    .major = 2,
    .minor = 16,
    .name = root_module,
    .num_of_funcs = nifs.len,
    .funcs = &(nifs[0]),
    .load = null,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = "beam.vanilla",
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit),
    .min_erts = "erts-15.0",
};

var callbacks: e.TWinDynNifCallbacks = undefined;

fn init(win_callbacks: *const e.TWinDynNifCallbacks) callconv(.c) *const e.ErlNifEntry {
    callbacks = win_callbacks.*;
    return &entry;
}

comptime {
    @export(&callbacks, .{ .name = "WinDynNifCallbacks" });
    @export(&init, .{ .name = "nif_init" });
}
