const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const result = kinda.result;
const py = @cImport({
    @cInclude("Python.h");
});

const root_module = "Elixir.Kinda.Python.Native";
const io_bound: u32 = 2;
var runtime_mutex: std.atomic.Mutex = .unlocked;

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

fn decrefOptional(object: ?*py.PyObject) void {
    if (object) |value| py.Py_DecRef(value);
}

fn hasExactType(object: *py.PyObject, python_type: *py.PyTypeObject) bool {
    return py.Py_TYPE(object) == python_type;
}

fn ensureRuntime() void {
    lock(&runtime_mutex);
    defer runtime_mutex.unlock();
    if (py.Py_IsInitialized() == 0) {
        py.Py_Initialize();
        _ = py.PyEval_SaveThread();
    }
}

const Interpreter = struct {
    pub const PtrType = *Interpreter;
    tstate: ?*py.PyThreadState,
    globals: ?*py.PyObject,
    mutex: std.atomic.Mutex = .unlocked,
    children: std.atomic.Value(usize) = .init(0),
    close_requested: std.atomic.Value(bool) = .init(false),

    fn close(self: *Interpreter) void {
        self.close_requested.store(true, .release);
        self.closeIfUnused();
    }

    fn closeIfUnused(self: *Interpreter) void {
        if (!self.close_requested.load(.acquire) or self.children.load(.acquire) != 0) return;
        lock(&runtime_mutex);
        defer runtime_mutex.unlock();
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.children.load(.acquire) != 0) return;
        const tstate = self.tstate orelse return;
        py.PyEval_AcquireThread(tstate);
        decrefOptional(self.globals);
        self.globals = null;
        py.Py_EndInterpreter(tstate);
        self.tstate = null;
    }

    fn releaseChild(self: *Interpreter) void {
        _ = self.children.fetchSub(1, .acq_rel);
        self.closeIfUnused();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Interpreter = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Value = struct {
    pub const PtrType = *Value;
    object: ?*py.PyObject,
    interpreter: beam.ResourceRef(Interpreter),
    mutex: std.atomic.Mutex = .unlocked,

    fn close(self: *Value) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        const object = self.object orelse return;
        const interpreter = self.interpreter.get();
        lock(&interpreter.mutex);
        const tstate = interpreter.tstate;
        if (tstate) |state| {
            py.PyEval_AcquireThread(state);
            py.Py_DecRef(object);
            py.PyEval_ReleaseThread(state);
        }
        interpreter.mutex.unlock();
        self.object = null;
        interpreter.releaseChild();
        self.interpreter.deinit();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Value = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const InterpreterKind = kinda.ResourceKind(Interpreter, "Elixir.Kinda.Python.Interpreter");
const ValueKind = kinda.ResourceKind(Value, "Elixir.Kinda.Python.Value");

const Error = error{ FailedToCreateInterpreter, FailedToCreateGlobals, FailedToEvaluate, FailedToCreateResource, ClosedInterpreter, ClosedValue, UnsupportedValue };

fn fetchInterpreter(environment: beam.env, term: beam.term) !*Interpreter {
    return beam.fetch_resource_ptr(*Interpreter, environment, InterpreterKind.resource.t, term);
}

fn fetchValue(environment: beam.env, term: beam.term) !*Value {
    return beam.fetch_resource_ptr(*Value, environment, ValueKind.resource.t, term);
}

fn createInterpreter(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    lock(&runtime_mutex);
    defer runtime_mutex.unlock();
    const main_tstate = py.PyThreadState_New(py.PyInterpreterState_Main()) orelse return Error.FailedToCreateInterpreter;
    _ = py.PyThreadState_Swap(main_tstate);
    var config = py.PyInterpreterConfig{ .use_main_obmalloc = 0, .allow_fork = 0, .allow_exec = 0, .allow_threads = 1, .allow_daemon_threads = 0, .check_multi_interp_extensions = 1, .gil = py.PyInterpreterConfig_OWN_GIL };
    var tstate: ?*py.PyThreadState = null;
    const status = py.Py_NewInterpreterFromConfig(&tstate, &config);
    if (py.PyStatus_Exception(status) != 0 or tstate == null) {
        _ = py.PyThreadState_Swap(main_tstate);
        py.PyThreadState_Clear(main_tstate);
        py.PyThreadState_DeleteCurrent();
        return Error.FailedToCreateInterpreter;
    }
    const globals = py.PyDict_New();
    if (globals == null) {
        py.Py_EndInterpreter(tstate);
        _ = py.PyThreadState_Swap(main_tstate);
        py.PyThreadState_Clear(main_tstate);
        py.PyThreadState_DeleteCurrent();
        return Error.FailedToCreateGlobals;
    }
    py.PyEval_ReleaseThread(tstate);
    _ = py.PyThreadState_Swap(main_tstate);
    py.PyThreadState_Clear(main_tstate);
    py.PyThreadState_DeleteCurrent();
    return InterpreterKind.resource.make(environment, .{ .tstate = tstate, .globals = globals }) catch return Error.FailedToCreateResource;
}

fn closeInterpreter(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchInterpreter(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn eval(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const interpreter = try fetchInterpreter(environment, args[0]);
    if (interpreter.close_requested.load(.acquire)) return Error.ClosedInterpreter;
    const code = try beam.get_char_slice(environment, args[1]);
    const terminated = try beam.allocator.dupeZ(u8, code);
    defer beam.allocator.free(terminated);
    lock(&interpreter.mutex);
    defer interpreter.mutex.unlock();
    const tstate = interpreter.tstate orelse return Error.ClosedInterpreter;
    py.PyEval_AcquireThread(tstate);
    const object = py.PyRun_StringFlags(terminated.ptr, py.Py_eval_input, interpreter.globals, interpreter.globals, null);
    if (object == null) {
        py.PyErr_Clear();
        py.PyEval_ReleaseThread(tstate);
        return Error.FailedToEvaluate;
    }
    py.PyEval_ReleaseThread(tstate);
    _ = interpreter.children.fetchAdd(1, .acq_rel);
    var interpreter_ref = beam.ResourceRef(Interpreter).init(interpreter);
    errdefer {
        interpreter_ref.deinit();
        interpreter.releaseChild();
    }
    return ValueKind.resource.make(environment, .{ .object = object, .interpreter = interpreter_ref }) catch return Error.FailedToCreateResource;
}

fn closeValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchValue(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn valueToTerm(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const value = try fetchValue(environment, args[0]);
    lock(&value.mutex);
    defer value.mutex.unlock();
    const object = value.object orelse return Error.ClosedValue;
    const interpreter = value.interpreter.get();
    lock(&interpreter.mutex);
    defer interpreter.mutex.unlock();
    const tstate = interpreter.tstate orelse return Error.ClosedInterpreter;
    py.PyEval_AcquireThread(tstate);
    defer py.PyEval_ReleaseThread(tstate);
    if (object == py.Py_None()) return beam.make_nil(environment);
    if (hasExactType(object, &py.PyBool_Type)) return beam.make_bool(environment, object == py.Py_True());
    if (hasExactType(object, &py.PyLong_Type)) return beam.make_i64(environment, py.PyLong_AsLongLong(object));
    if (hasExactType(object, &py.PyUnicode_Type)) {
        var length: py.Py_ssize_t = 0;
        const bytes = py.PyUnicode_AsUTF8AndSize(object, &length) orelse return Error.UnsupportedValue;
        return beam.make_slice(environment, bytes[0..@intCast(length)]);
    }
    return Error.UnsupportedValue;
}

fn isolatedEval(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const code = try beam.get_char_slice(environment, args[0]);
    const terminated = try beam.allocator.dupeZ(u8, code);
    defer beam.allocator.free(terminated);
    const main_tstate = py.PyThreadState_New(py.PyInterpreterState_Main()) orelse return Error.FailedToCreateInterpreter;
    _ = py.PyThreadState_Swap(main_tstate);
    var config = py.PyInterpreterConfig{ .use_main_obmalloc = 0, .allow_fork = 0, .allow_exec = 0, .allow_threads = 1, .allow_daemon_threads = 0, .check_multi_interp_extensions = 1, .gil = py.PyInterpreterConfig_OWN_GIL };
    var tstate: ?*py.PyThreadState = null;
    const status = py.Py_NewInterpreterFromConfig(&tstate, &config);
    if (py.PyStatus_Exception(status) != 0 or tstate == null) {
        _ = py.PyThreadState_Swap(main_tstate);
        py.PyThreadState_Clear(main_tstate);
        py.PyThreadState_DeleteCurrent();
        return Error.FailedToCreateInterpreter;
    }
    const globals = py.PyDict_New();
    const object = if (globals) |scope| py.PyRun_StringFlags(terminated.ptr, py.Py_eval_input, scope, scope, null) else null;
    if (object == null) {
        py.PyErr_Clear();
        decrefOptional(globals);
        py.Py_EndInterpreter(tstate);
        _ = py.PyThreadState_Swap(main_tstate);
        py.PyThreadState_Clear(main_tstate);
        py.PyThreadState_DeleteCurrent();
        return Error.FailedToEvaluate;
    }
    const term = if (hasExactType(object, &py.PyLong_Type))
        beam.make_i64(environment, py.PyLong_AsLongLong(object))
    else if (hasExactType(object, &py.PyUnicode_Type)) blk: {
        var length: py.Py_ssize_t = 0;
        const bytes = py.PyUnicode_AsUTF8AndSize(object, &length) orelse break :blk beam.make_nil(environment);
        break :blk beam.make_slice(environment, bytes[0..@intCast(length)]);
    } else beam.make_nil(environment);
    py.Py_DecRef(object);
    decrefOptional(globals);
    py.Py_EndInterpreter(tstate);
    _ = py.PyThreadState_Swap(main_tstate);
    py.PyThreadState_Clear(main_tstate);
    py.PyThreadState_DeleteCurrent();
    return term;
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
    result.nif_with_flags("create_interpreter", 0, createInterpreter, io_bound).entry,
    result.nif_with_flags("close_interpreter", 1, closeInterpreter, io_bound).entry,
    result.nif_with_flags("eval", 2, eval, io_bound).entry,
    result.nif_with_flags("close_value", 1, closeValue, io_bound).entry,
    result.nif_with_flags("value_to_term", 1, valueToTerm, io_bound).entry,
    result.nif_with_flags("isolated_eval", 1, isolatedEval, io_bound).entry,
};

const Resources = kinda.ResourceRegistry(.{
    kinda.ResourceRegistration{ .kind = InterpreterKind },
    kinda.ResourceRegistration{ .kind = ValueKind },
});

fn nifLoad(environment: beam.env, _: [*c]?*anyopaque, _: beam.term) callconv(.c) c_int {
    ensureRuntime();
    return Resources.open(environment);
}
fn nifUpgrade(environment: beam.env, private_data: [*c]?*anyopaque, _: [*c]?*anyopaque, load_info: beam.term) callconv(.c) c_int {
    return nifLoad(environment, private_data, load_info);
}

const nif_exports = kinda.EntryExports(.{
    .name = root_module,
    .nifs = all_nifs,
    .load = nifLoad,
    .upgrade = nifUpgrade,
});

comptime {
    _ = nif_exports;
}
