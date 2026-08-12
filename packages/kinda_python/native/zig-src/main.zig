const std = @import("std");
const builtin = @import("builtin");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;
const py = @cImport({
    @cInclude("Python.h");
});

const root_module = "Elixir.Kinda.Python.Native";
var runtime_mutex: std.atomic.Mutex = .unlocked;

fn lockRuntime() void {
    while (!runtime_mutex.tryLock()) std.atomic.spinLoopHint();
}

fn ensureRuntime() void {
    lockRuntime();
    defer runtime_mutex.unlock();

    if (py.Py_IsInitialized() == 0) {
        py.Py_Initialize();
        _ = py.PyEval_SaveThread();
    }
}

fn version(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_slice(environment, std.mem.span(py.Py_GetVersion()));
}

fn initialized(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_bool(environment, py.Py_IsInitialized() != 0);
}

fn freeThreadedBuild(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_bool(environment, @hasDecl(py, "Py_GIL_DISABLED"));
}

const all_nifs = .{
    result.nif("version", 0, version).entry,
    result.nif("initialized?", 0, initialized).entry,
    result.nif("free_threaded_build?", 0, freeThreadedBuild).entry,
};
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

fn nifLoad(_: beam.env, _: [*c]?*anyopaque, _: beam.term) callconv(.c) c_int {
    ensureRuntime();
    return 0;
}

const entry = e.ErlNifEntry{
    .major = 2,
    .minor = 16,
    .name = root_module,
    .num_of_funcs = nifs.len,
    .funcs = &(nifs[0]),
    .load = nifLoad,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = "beam.vanilla",
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit),
    .min_erts = "erts-15.0",
};

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
