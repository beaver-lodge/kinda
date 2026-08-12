const std = @import("std");
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

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

const VM = struct {
    pub const PtrType = *VM;
    state: ?*mrb.mrb_state,
    mutex: std.atomic.Mutex = .unlocked,
    children: std.atomic.Value(usize) = .init(0),
    close_requested: std.atomic.Value(bool) = .init(false),

    fn close(self: *VM) void {
        self.close_requested.store(true, .release);
        self.closeIfUnused();
    }

    fn closeIfUnused(self: *VM) void {
        if (!self.close_requested.load(.acquire) or self.children.load(.acquire) != 0) return;
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.children.load(.acquire) != 0) return;
        const state = self.state orelse return;
        mrb.kinda_mruby_close(state);
        self.state = null;
    }

    fn releaseChild(self: *VM) void {
        _ = self.children.fetchSub(1, .acq_rel);
        self.closeIfUnused();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *VM = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Value = struct {
    pub const PtrType = *Value;
    value: mrb.kinda_mruby_value,
    registered: bool,
    vm: beam.ResourceRef(VM),
    mutex: std.atomic.Mutex = .unlocked,
    closed: bool = false,

    fn close(self: *Value) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.closed) return;
        const vm = self.vm.get();
        lock(&vm.mutex);
        if (vm.state) |state| {
            if (self.registered) mrb.kinda_mruby_gc_unregister(state, self.value);
        }
        vm.mutex.unlock();
        self.closed = true;
        vm.releaseChild();
        self.vm.deinit();
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

const VMKind = kinda.ResourceKind(VM, "Elixir.Kinda.MRuby.VM");
const ValueKind = kinda.ResourceKind(Value, "Elixir.Kinda.MRuby.Value");
const BytecodeKind = kinda.ResourceKind(Bytecode, "Elixir.Kinda.MRuby.Bytecode");
const Error = error{ FailedToCreateVM, FailedToEvaluate, FailedToCompile, FailedToCreateResource, ClosedVM, ClosedValue, ClosedBytecode, UnsupportedValue };

fn fetchVM(environment: beam.env, term: beam.term) !*VM {
    return beam.fetch_resource_ptr(*VM, environment, VMKind.resource.t, term);
}

fn fetchValue(environment: beam.env, term: beam.term) !*Value {
    return beam.fetch_resource_ptr(*Value, environment, ValueKind.resource.t, term);
}

fn fetchBytecode(environment: beam.env, term: beam.term) !*Bytecode {
    return beam.fetch_resource_ptr(*Bytecode, environment, BytecodeKind.resource.t, term);
}

fn makeValue(environment: beam.env, vm: *VM, state: *mrb.mrb_state, value: mrb.kinda_mruby_value) !beam.term {
    const registered = mrb.kinda_mruby_immediate(value) == 0;
    if (registered) mrb.kinda_mruby_gc_register(state, value);
    _ = vm.children.fetchAdd(1, .acq_rel);
    var vm_ref = beam.ResourceRef(VM).init(vm);
    errdefer {
        if (registered) mrb.kinda_mruby_gc_unregister(state, value);
        vm_ref.deinit();
        vm.releaseChild();
    }
    return ValueKind.resource.make(environment, .{ .value = value, .registered = registered, .vm = vm_ref }) catch return Error.FailedToCreateResource;
}

fn createVM(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    const state = mrb.kinda_mruby_open() orelse return Error.FailedToCreateVM;
    return VMKind.resource.make(environment, .{ .state = state }) catch {
        mrb.kinda_mruby_close(state);
        return Error.FailedToCreateResource;
    };
}

fn closeVM(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchVM(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn evalValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const vm = try fetchVM(environment, args[0]);
    if (vm.close_requested.load(.acquire)) return Error.ClosedVM;
    const code = try beam.get_char_slice(environment, args[1]);
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    const state = vm.state orelse return Error.ClosedVM;
    const arena = mrb.kinda_mruby_arena_save(state);
    defer mrb.kinda_mruby_arena_restore(state, arena);
    var raised: c_int = 0;
    const value = mrb.kinda_mruby_eval(state, code.ptr, code.len, &raised);
    if (raised != 0 or mrb.kinda_mruby_raised(state) != 0) {
        mrb.kinda_mruby_clear_exception(state);
        return Error.FailedToEvaluate;
    }
    return makeValue(environment, vm, state, value);
}

fn compileBytecode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const code = try beam.get_char_slice(environment, args[0]);
    const state = mrb.kinda_mruby_open() orelse return Error.FailedToCreateVM;
    defer mrb.kinda_mruby_close(state);
    var compiled: [*c]u8 = null;
    var size: usize = 0;
    if (mrb.kinda_mruby_compile(state, code.ptr, code.len, &compiled, &size) != 0 or compiled == null) return Error.FailedToCompile;
    defer mrb.kinda_mruby_free(state, compiled);
    const bytes = beam.allocator.dupe(u8, compiled[0..size]) catch return Error.FailedToCreateResource;
    errdefer beam.allocator.free(bytes);
    return BytecodeKind.resource.make(environment, .{ .bytes = bytes }) catch return Error.FailedToCreateResource;
}

fn closeBytecode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchBytecode(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn runBytecode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const vm = try fetchVM(environment, args[0]);
    if (vm.close_requested.load(.acquire)) return Error.ClosedVM;
    const bytecode = try fetchBytecode(environment, args[1]);
    lock(&bytecode.mutex);
    defer bytecode.mutex.unlock();
    if (bytecode.closed) return Error.ClosedBytecode;
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    const state = vm.state orelse return Error.ClosedVM;
    const arena = mrb.kinda_mruby_arena_save(state);
    defer mrb.kinda_mruby_arena_restore(state, arena);
    var raised: c_int = 0;
    const value = mrb.kinda_mruby_run_bytecode_protected(state, bytecode.bytes.ptr, bytecode.bytes.len, &raised);
    if (raised != 0 or mrb.kinda_mruby_raised(state) != 0) {
        mrb.kinda_mruby_clear_exception(state);
        return Error.FailedToEvaluate;
    }
    return makeValue(environment, vm, state, value);
}

fn closeValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchValue(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn valueToTerm(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const resource = try fetchValue(environment, args[0]);
    lock(&resource.mutex);
    defer resource.mutex.unlock();
    if (resource.closed) return Error.ClosedValue;
    const vm = resource.vm.get();
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    if (vm.state == null) return Error.ClosedVM;
    const value = resource.value;
    return switch (mrb.kinda_mruby_type(value)) {
        mrb.KINDA_MRUBY_TT_FALSE => if (mrb.kinda_mruby_nil(value) != 0) beam.make_nil(environment) else beam.make_bool(environment, false),
        mrb.KINDA_MRUBY_TT_TRUE => beam.make_bool(environment, true),
        mrb.KINDA_MRUBY_TT_INTEGER => beam.make_i64(environment, mrb.kinda_mruby_integer(value)),
        mrb.KINDA_MRUBY_TT_STRING => beam.make_slice(environment, mrb.kinda_mruby_string_ptr(value)[0..mrb.kinda_mruby_string_len(value)]),
        else => Error.UnsupportedValue,
    };
}

fn ephemeralEval(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
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

const all_nifs = .{
    result.nif("version", 0, version).entry,
    result.nif_with_flags("eval", 1, ephemeralEval, cpu_bound).entry,
    result.nif_with_flags("create_vm", 0, createVM, cpu_bound).entry,
    result.nif_with_flags("close_vm", 1, closeVM, cpu_bound).entry,
    result.nif_with_flags("eval_value", 2, evalValue, cpu_bound).entry,
    result.nif_with_flags("close_value", 1, closeValue, cpu_bound).entry,
    result.nif_with_flags("value_to_term", 1, valueToTerm, cpu_bound).entry,
    result.nif_with_flags("compile_bytecode", 1, compileBytecode, cpu_bound).entry,
    result.nif_with_flags("close_bytecode", 1, closeBytecode, cpu_bound).entry,
    result.nif_with_flags("run_bytecode", 2, runBytecode, cpu_bound).entry,
};
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

fn nifLoad(environment: beam.env, _: [*c]?*anyopaque, _: beam.term) callconv(.c) c_int {
    VMKind.open(environment);
    ValueKind.open(environment);
    BytecodeKind.open(environment);
    return if (VMKind.resource.t == null or ValueKind.resource.t == null or BytecodeKind.resource.t == null) 1 else 0;
}

fn nifUpgrade(environment: beam.env, private_data: [*c]?*anyopaque, _: [*c]?*anyopaque, load_info: beam.term) callconv(.c) c_int {
    return nifLoad(environment, private_data, load_info);
}

const entry = e.ErlNifEntry{ .major = 2, .minor = 16, .name = root_module, .num_of_funcs = nifs.len, .funcs = &(nifs[0]), .load = nifLoad, .reload = null, .upgrade = nifUpgrade, .unload = null, .vm_variant = "beam.vanilla", .options = 1, .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit), .min_erts = "erts-15.0" };

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
