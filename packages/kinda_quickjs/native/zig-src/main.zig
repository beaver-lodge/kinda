const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const result = kinda.result;
const quickjs = @cImport({
    @cInclude("kinda_quickjs_shim.h");
});

const root_module = "Elixir.Kinda.QuickJS.Native";
const cpu_bound: u32 = 1;
const Error = error{ FailedToEvaluate, UnsupportedValue };

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

const Runtime = struct {
    pub const PtrType = *Runtime;
    handle: ?*quickjs.kinda_quickjs_runtime,
    mutex: std.atomic.Mutex = .unlocked,
    contexts: std.atomic.Value(usize) = .init(0),
    close_requested: std.atomic.Value(bool) = .init(false),

    fn close(self: *Runtime) void {
        self.close_requested.store(true, .release);
        self.closeIfUnused();
    }

    fn closeIfUnused(self: *Runtime) void {
        if (!self.close_requested.load(.acquire) or self.contexts.load(.acquire) != 0) return;
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.contexts.load(.acquire) != 0) return;
        if (self.handle) |handle| quickjs.kinda_quickjs_runtime_destroy(handle);
        self.handle = null;
    }

    fn releaseContext(self: *Runtime) void {
        _ = self.contexts.fetchSub(1, .acq_rel);
        self.closeIfUnused();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Runtime = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Context = struct {
    pub const PtrType = *Context;
    handle: ?*quickjs.kinda_quickjs_context,
    runtime: beam.ResourceRef(Runtime),
    mutex: std.atomic.Mutex = .unlocked,
    closed: bool = false,
    values: std.atomic.Value(usize) = .init(0),
    close_requested: std.atomic.Value(bool) = .init(false),

    fn close(self: *Context) void {
        self.close_requested.store(true, .release);
        self.closeIfUnused();
    }

    fn closeIfUnused(self: *Context) void {
        if (!self.close_requested.load(.acquire) or self.values.load(.acquire) != 0) return;
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.closed or self.values.load(.acquire) != 0) return;
        const runtime = self.runtime.get();
        lock(&runtime.mutex);
        if (self.handle) |handle| quickjs.kinda_quickjs_context_destroy(handle);
        self.handle = null;
        runtime.mutex.unlock();
        self.closed = true;
        runtime.releaseContext();
        self.runtime.deinit();
    }

    fn releaseValue(self: *Context) void {
        _ = self.values.fetchSub(1, .acq_rel);
        self.closeIfUnused();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Context = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Value = struct {
    pub const PtrType = *Value;
    handle: ?*quickjs.kinda_quickjs_value,
    context: beam.ResourceRef(Context),
    mutex: std.atomic.Mutex = .unlocked,
    closed: bool = false,

    fn close(self: *Value) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.closed) return;
        const context = self.context.get();
        const runtime = context.runtime.get();
        lock(&runtime.mutex);
        if (self.handle) |handle| quickjs.kinda_quickjs_value_destroy(handle);
        self.handle = null;
        runtime.mutex.unlock();
        self.closed = true;
        context.releaseValue();
        self.context.deinit();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Value = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Bytecode = struct {
    pub const PtrType = *Bytecode;
    bytes: []u8,
    mutex: std.atomic.Mutex = .unlocked,
    closed: bool = false,
    fn close(self: *Bytecode) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.closed) return;
        beam.allocator.free(self.bytes);
        self.closed = true;
    }
    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Bytecode = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

comptime {
    kinda.validateDeferredCloseParent(Runtime, .{
        .counter = "contexts",
        .close = Runtime.close,
        .close_if_unused = Runtime.closeIfUnused,
        .release = Runtime.releaseContext,
    });
    kinda.validateDeferredCloseParent(Context, .{
        .counter = "values",
        .close = Context.close,
        .close_if_unused = Context.closeIfUnused,
        .release = Context.releaseValue,
    });
}

const RuntimeKind = kinda.ResourceKind(Runtime, "Elixir.Kinda.QuickJS.Runtime");
const ContextKind = kinda.ResourceKind(Context, "Elixir.Kinda.QuickJS.Context");
const ValueKind = kinda.ResourceKind(Value, "Elixir.Kinda.QuickJS.Value");
const BytecodeKind = kinda.ResourceKind(Bytecode, "Elixir.Kinda.QuickJS.Bytecode");

fn makeValue(environment: beam.env, value: quickjs.struct_kinda_quickjs_result) !beam.term {
    return switch (value.type) {
        quickjs.KINDA_QUICKJS_UNDEFINED => beam.make_atom(environment, "undefined"),
        quickjs.KINDA_QUICKJS_NULL => beam.make_nil(environment),
        quickjs.KINDA_QUICKJS_BOOLEAN => beam.make_bool(environment, value.boolean_value != 0),
        quickjs.KINDA_QUICKJS_INTEGER => beam.make_i64(environment, value.integer_value),
        quickjs.KINDA_QUICKJS_NUMBER => beam.make_f64(environment, value.number_value),
        quickjs.KINDA_QUICKJS_STRING => beam.make_slice(environment, value.string_value[0..value.string_length]),
        else => Error.UnsupportedValue,
    };
}

fn eval(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const code = try beam.get_char_slice(environment, args[0]);
    var value: quickjs.struct_kinda_quickjs_result = std.mem.zeroes(quickjs.struct_kinda_quickjs_result);
    if (quickjs.kinda_quickjs_eval(code.ptr, code.len, &value) != 0) return Error.FailedToEvaluate;
    defer quickjs.kinda_quickjs_result_release(&value);
    return makeValue(environment, value);
}

fn createRuntime(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const memory_limit = try beam.get_usize(environment, args[0]);
    const stack_limit = try beam.get_usize(environment, args[1]);
    const handle = quickjs.kinda_quickjs_runtime_create(memory_limit, stack_limit) orelse return error.OutOfMemory;
    return RuntimeKind.resource.make(environment, .{ .handle = handle }) catch {
        quickjs.kinda_quickjs_runtime_destroy(handle);
        return error.OutOfMemory;
    };
}

fn closeRuntime(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try beam.fetch_resource_ptr(*Runtime, environment, RuntimeKind.resource.t, args[0])).close();
    return beam.make_ok(environment);
}

fn runtimeStats(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const runtime = try beam.fetch_resource_ptr(*Runtime, environment, RuntimeKind.resource.t, args[0]);
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const handle = runtime.handle orelse return error.ClosedRuntime;
    var allocations: usize = 0;
    var live_bytes: usize = 0;
    var limit: usize = 0;
    quickjs.kinda_quickjs_runtime_stats(handle, &allocations, &live_bytes, &limit);
    var terms = [_]beam.term{
        beam.make_usize(environment, allocations),
        beam.make_usize(environment, live_bytes),
        beam.make_usize(environment, limit),
    };
    return beam.make_tuple(environment, &terms);
}

fn createContext(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const runtime = try beam.fetch_resource_ptr(*Runtime, environment, RuntimeKind.resource.t, args[0]);
    if (runtime.close_requested.load(.acquire)) return error.ClosedRuntime;
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const runtime_handle = runtime.handle orelse return error.ClosedRuntime;
    const handle = quickjs.kinda_quickjs_context_create(runtime_handle) orelse return error.OutOfMemory;
    _ = runtime.contexts.fetchAdd(1, .acq_rel);
    var runtime_ref = beam.ResourceRef(Runtime).init(runtime);
    errdefer {
        quickjs.kinda_quickjs_context_destroy(handle);
        runtime_ref.deinit();
        runtime.releaseContext();
    }
    return ContextKind.resource.make(environment, .{ .handle = handle, .runtime = runtime_ref }) catch return error.OutOfMemory;
}

fn evalContext(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const context = try beam.fetch_resource_ptr(*Context, environment, ContextKind.resource.t, args[0]);
    const code = try beam.get_char_slice(environment, args[1]);
    const interrupt_budget = try beam.get_u64(environment, args[2]);
    lock(&context.mutex);
    defer context.mutex.unlock();
    if (context.closed) return error.ClosedContext;
    const runtime = context.runtime.get();
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const runtime_handle = runtime.handle orelse return error.ClosedRuntime;
    const context_handle = context.handle orelse return error.ClosedContext;
    var value: quickjs.struct_kinda_quickjs_result = std.mem.zeroes(quickjs.struct_kinda_quickjs_result);
    if (quickjs.kinda_quickjs_context_eval(runtime_handle, context_handle, code.ptr, code.len, interrupt_budget, &value) != 0) return Error.FailedToEvaluate;
    defer quickjs.kinda_quickjs_result_release(&value);
    return makeValue(environment, value);
}

fn closeContext(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try beam.fetch_resource_ptr(*Context, environment, ContextKind.resource.t, args[0])).close();
    return beam.make_ok(environment);
}

fn createValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const context = try beam.fetch_resource_ptr(*Context, environment, ContextKind.resource.t, args[0]);
    if (context.close_requested.load(.acquire)) return error.ClosedContext;
    const code = try beam.get_char_slice(environment, args[1]);
    lock(&context.mutex);
    defer context.mutex.unlock();
    const runtime = context.runtime.get();
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const runtime_handle = runtime.handle orelse return error.ClosedRuntime;
    const context_handle = context.handle orelse return error.ClosedContext;
    const handle = quickjs.kinda_quickjs_value_eval(runtime_handle, context_handle, code.ptr, code.len) orelse return Error.FailedToEvaluate;
    _ = context.values.fetchAdd(1, .acq_rel);
    var context_ref = beam.ResourceRef(Context).init(context);
    errdefer {
        quickjs.kinda_quickjs_value_destroy(handle);
        context_ref.deinit();
        context.releaseValue();
    }
    return ValueKind.resource.make(environment, .{ .handle = handle, .context = context_ref }) catch return error.OutOfMemory;
}

fn exportValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const value = try beam.fetch_resource_ptr(*Value, environment, ValueKind.resource.t, args[0]);
    lock(&value.mutex);
    defer value.mutex.unlock();
    if (value.closed) return error.ClosedValue;
    const context = value.context.get();
    const runtime = context.runtime.get();
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const handle = value.handle orelse return error.ClosedValue;
    var exported: quickjs.struct_kinda_quickjs_result = std.mem.zeroes(quickjs.struct_kinda_quickjs_result);
    if (quickjs.kinda_quickjs_value_export(handle, &exported) != 0) return error.FailedToExport;
    defer quickjs.kinda_quickjs_result_release(&exported);
    return makeValue(environment, exported);
}

fn promiseState(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const value = try beam.fetch_resource_ptr(*Value, environment, ValueKind.resource.t, args[0]);
    lock(&value.mutex);
    defer value.mutex.unlock();
    if (value.closed) return error.ClosedValue;
    const context = value.context.get();
    const runtime = context.runtime.get();
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const handle = value.handle orelse return error.ClosedValue;
    return beam.make_atom(environment, switch (quickjs.kinda_quickjs_promise_state(handle)) {
        0 => "pending",
        1 => "fulfilled",
        2 => "rejected",
        else => "not_promise",
    });
}

fn promiseResult(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const value = try beam.fetch_resource_ptr(*Value, environment, ValueKind.resource.t, args[0]);
    lock(&value.mutex);
    defer value.mutex.unlock();
    if (value.closed) return error.ClosedValue;
    const context = value.context.get();
    const runtime = context.runtime.get();
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const handle = value.handle orelse return error.ClosedValue;
    var exported: quickjs.struct_kinda_quickjs_result = std.mem.zeroes(quickjs.struct_kinda_quickjs_result);
    if (quickjs.kinda_quickjs_promise_result(handle, &exported) != 0) return error.FailedToExport;
    defer quickjs.kinda_quickjs_result_release(&exported);
    return makeValue(environment, exported);
}

fn runJobs(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const runtime = try beam.fetch_resource_ptr(*Runtime, environment, RuntimeKind.resource.t, args[0]);
    const limit = try beam.get_usize(environment, args[1]);
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const handle = runtime.handle orelse return error.ClosedRuntime;
    var executed: usize = 0;
    if (quickjs.kinda_quickjs_run_jobs(handle, limit, &executed) != 0) return error.FailedJob;
    return beam.make_usize(environment, executed);
}

fn closeValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try beam.fetch_resource_ptr(*Value, environment, ValueKind.resource.t, args[0])).close();
    return beam.make_ok(environment);
}

fn registerModule(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const runtime = try beam.fetch_resource_ptr(*Runtime, environment, RuntimeKind.resource.t, args[0]);
    const name = try beam.get_char_slice(environment, args[1]);
    const source = try beam.get_char_slice(environment, args[2]);
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const handle = runtime.handle orelse return error.ClosedRuntime;
    if (quickjs.kinda_quickjs_register_module(handle, name.ptr, name.len, source.ptr, source.len) != 0) return error.OutOfMemory;
    return beam.make_ok(environment);
}

fn evalModule(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const context = try beam.fetch_resource_ptr(*Context, environment, ContextKind.resource.t, args[0]);
    const source = try beam.get_char_slice(environment, args[1]);
    lock(&context.mutex);
    defer context.mutex.unlock();
    if (context.closed) return error.ClosedContext;
    const runtime = context.runtime.get();
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const runtime_handle = runtime.handle orelse return error.ClosedRuntime;
    const context_handle = context.handle orelse return error.ClosedContext;
    if (quickjs.kinda_quickjs_eval_module(runtime_handle, context_handle, source.ptr, source.len) != 0) return Error.FailedToEvaluate;
    return beam.make_ok(environment);
}

fn compileBytecode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const context = try beam.fetch_resource_ptr(*Context, environment, ContextKind.resource.t, args[0]);
    const source = try beam.get_char_slice(environment, args[1]);
    lock(&context.mutex);
    defer context.mutex.unlock();
    const runtime = context.runtime.get();
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const context_handle = context.handle orelse return error.ClosedContext;
    var compiled: [*c]u8 = null;
    var size: usize = 0;
    if (quickjs.kinda_quickjs_compile(context_handle, source.ptr, source.len, &compiled, &size) != 0 or compiled == null) return error.FailedToCompile;
    defer quickjs.kinda_quickjs_free(compiled);
    const signature = "QuickJS 2026-06-04\x00";
    const bytes = try beam.allocator.alloc(u8, signature.len + size);
    errdefer beam.allocator.free(bytes);
    @memcpy(bytes[0..signature.len], signature);
    @memcpy(bytes[signature.len..], compiled[0..size]);
    return BytecodeKind.resource.make(environment, .{ .bytes = bytes }) catch return error.OutOfMemory;
}

fn runBytecode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const context = try beam.fetch_resource_ptr(*Context, environment, ContextKind.resource.t, args[0]);
    const bytecode = try beam.fetch_resource_ptr(*Bytecode, environment, BytecodeKind.resource.t, args[1]);
    lock(&bytecode.mutex);
    defer bytecode.mutex.unlock();
    if (bytecode.closed) return error.ClosedBytecode;
    const signature = "QuickJS 2026-06-04\x00";
    if (bytecode.bytes.len < signature.len or !std.mem.eql(u8, bytecode.bytes[0..signature.len], signature)) return error.IncompatibleBytecode;
    lock(&context.mutex);
    defer context.mutex.unlock();
    const runtime = context.runtime.get();
    lock(&runtime.mutex);
    defer runtime.mutex.unlock();
    const context_handle = context.handle orelse return error.ClosedContext;
    var exported: quickjs.struct_kinda_quickjs_result = std.mem.zeroes(quickjs.struct_kinda_quickjs_result);
    const payload = bytecode.bytes[signature.len..];
    if (quickjs.kinda_quickjs_run_bytecode(context_handle, payload.ptr, payload.len, &exported) != 0) return Error.FailedToEvaluate;
    defer quickjs.kinda_quickjs_result_release(&exported);
    return makeValue(environment, exported);
}

fn closeBytecode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try beam.fetch_resource_ptr(*Bytecode, environment, BytecodeKind.resource.t, args[0])).close();
    return beam.make_ok(environment);
}

fn version(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_slice(environment, std.mem.span(quickjs.kinda_quickjs_version()));
}

const all_nifs = .{
    result.nif("version", 0, version).entry,
    result.nif_with_flags("eval", 1, eval, cpu_bound).entry,
    result.nif_with_flags("create_runtime", 2, createRuntime, cpu_bound).entry,
    result.nif_with_flags("close_runtime", 1, closeRuntime, cpu_bound).entry,
    result.nif_with_flags("runtime_stats", 1, runtimeStats, cpu_bound).entry,
    result.nif_with_flags("create_context", 1, createContext, cpu_bound).entry,
    result.nif_with_flags("eval_context", 3, evalContext, cpu_bound).entry,
    result.nif_with_flags("close_context", 1, closeContext, cpu_bound).entry,
    result.nif_with_flags("create_value", 2, createValue, cpu_bound).entry,
    result.nif_with_flags("export_value", 1, exportValue, cpu_bound).entry,
    result.nif_with_flags("promise_state", 1, promiseState, cpu_bound).entry,
    result.nif_with_flags("promise_result", 1, promiseResult, cpu_bound).entry,
    result.nif_with_flags("run_jobs", 2, runJobs, cpu_bound).entry,
    result.nif_with_flags("close_value", 1, closeValue, cpu_bound).entry,
    result.nif_with_flags("register_module", 3, registerModule, cpu_bound).entry,
    result.nif_with_flags("eval_module", 2, evalModule, cpu_bound).entry,
    result.nif_with_flags("compile_bytecode", 2, compileBytecode, cpu_bound).entry,
    result.nif_with_flags("run_bytecode", 2, runBytecode, cpu_bound).entry,
    result.nif_with_flags("close_bytecode", 1, closeBytecode, cpu_bound).entry,
};

const Resources = kinda.ResourceRegistry(.{
    kinda.ResourceRegistration{ .kind = RuntimeKind },
    kinda.ResourceRegistration{ .kind = ContextKind },
    kinda.ResourceRegistration{ .kind = ValueKind },
    kinda.ResourceRegistration{ .kind = BytecodeKind },
});

fn nifLoad(environment: beam.env, _: [*c]?*anyopaque, _: beam.term) callconv(.c) c_int {
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
