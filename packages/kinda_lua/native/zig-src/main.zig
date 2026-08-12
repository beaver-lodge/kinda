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

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

const VM = struct {
    pub const PtrType = *VM;
    state: ?*lua.lua_State,
    allocator: *lua.kinda_lua_allocator,
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
        if (self.state) |state| lua.kinda_lua_close(state);
        self.state = null;
    }

    fn releaseChild(self: *VM) void {
        _ = self.children.fetchSub(1, .acq_rel);
        self.closeIfUnused();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *VM = @ptrCast(@alignCast(object orelse return));
        self.close();
        lua.kinda_lua_allocator_destroy(self.allocator);
    }
};

const Coroutine = struct {
    pub const PtrType = *Coroutine;
    reference: c_int,
    vm: beam.ResourceRef(VM),
    mutex: std.atomic.Mutex = .unlocked,
    closed: bool = false,

    fn close(self: *Coroutine) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.closed) return;
        const vm = self.vm.get();
        lock(&vm.mutex);
        if (vm.state) |state| lua.kinda_lua_coroutine_release(state, self.reference);
        vm.mutex.unlock();
        self.closed = true;
        vm.releaseChild();
        self.vm.deinit();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Coroutine = @ptrCast(@alignCast(object orelse return));
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

const Userdata = struct {
    pub const PtrType = *Userdata;
    reference: c_int,
    vm: beam.ResourceRef(VM),
    mutex: std.atomic.Mutex = .unlocked,
    closed: bool = false,

    fn close(self: *Userdata) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.closed) return;
        const vm = self.vm.get();
        lock(&vm.mutex);
        if (vm.state) |state| lua.kinda_lua_userdata_release(state, self.reference);
        vm.mutex.unlock();
        self.closed = true;
        vm.releaseChild();
        self.vm.deinit();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Userdata = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const VMKind = kinda.ResourceKind(VM, "Elixir.Kinda.Lua.VM");
const CoroutineKind = kinda.ResourceKind(Coroutine, "Elixir.Kinda.Lua.Coroutine");
const BytecodeKind = kinda.ResourceKind(Bytecode, "Elixir.Kinda.Lua.Bytecode");
const UserdataKind = kinda.ResourceKind(Userdata, "Elixir.Kinda.Lua.Userdata");

fn makeLuaValue(environment: beam.env, value: lua.struct_kinda_lua_result) !beam.term {
    return switch (value.type) {
        lua.KINDA_LUA_NIL => beam.make_nil(environment),
        lua.KINDA_LUA_BOOLEAN => beam.make_bool(environment, value.boolean_value != 0),
        lua.KINDA_LUA_INTEGER => beam.make_i64(environment, value.integer_value),
        lua.KINDA_LUA_NUMBER => beam.make_f64(environment, value.number_value),
        lua.KINDA_LUA_STRING => beam.make_slice(environment, value.string_value[0..value.string_length]),
        else => Error.UnsupportedValue,
    };
}

fn eval(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const code = try beam.get_char_slice(environment, args[0]);
    var value: lua.struct_kinda_lua_result = std.mem.zeroes(lua.struct_kinda_lua_result);
    if (lua.kinda_lua_eval(code.ptr, code.len, &value) != 0) return Error.FailedToEvaluate;
    defer lua.kinda_lua_result_release(&value);
    return makeLuaValue(environment, value);
}

fn createVM(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const budget = try beam.get_usize(environment, args[0]);
    const allocator = lua.kinda_lua_allocator_create(budget) orelse return error.OutOfMemory;
    errdefer lua.kinda_lua_allocator_destroy(allocator);
    const state = lua.kinda_lua_open(allocator) orelse return error.OutOfMemory;
    return VMKind.resource.make(environment, .{ .state = state, .allocator = allocator }) catch {
        lua.kinda_lua_close(state);
        return error.OutOfMemory;
    };
}

fn closeVM(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const vm = try beam.fetch_resource_ptr(*VM, environment, VMKind.resource.t, args[0]);
    vm.close();
    return beam.make_ok(environment);
}

fn allocatorStats(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const vm = try beam.fetch_resource_ptr(*VM, environment, VMKind.resource.t, args[0]);
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    var terms = [_]beam.term{
        beam.make_usize(environment, lua.kinda_lua_allocator_calls(vm.allocator)),
        beam.make_usize(environment, lua.kinda_lua_allocator_live_bytes(vm.allocator)),
        beam.make_usize(environment, lua.kinda_lua_allocator_peak_bytes(vm.allocator)),
    };
    return beam.make_tuple(environment, &terms);
}

fn evalVM(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const vm = try beam.fetch_resource_ptr(*VM, environment, VMKind.resource.t, args[0]);
    const code = try beam.get_char_slice(environment, args[1]);
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    const state = vm.state orelse return error.ClosedVM;
    var count: c_int = 0;
    if (lua.kinda_lua_eval_state(state, code.ptr, code.len, &count) != 0) return Error.FailedToEvaluate;
    defer lua.kinda_lua_clear_stack(state);
    const terms = try beam.allocator.alloc(beam.term, @intCast(count));
    defer beam.allocator.free(terms);
    for (terms, 1..) |*term, index| {
        var value: lua.struct_kinda_lua_result = std.mem.zeroes(lua.struct_kinda_lua_result);
        lua.kinda_lua_result_at(state, @intCast(index), &value);
        term.* = try makeLuaValue(environment, value);
    }
    return beam.make_term_list(environment, terms);
}

fn createCoroutine(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const vm = try beam.fetch_resource_ptr(*VM, environment, VMKind.resource.t, args[0]);
    if (vm.close_requested.load(.acquire)) return error.ClosedVM;
    const code = try beam.get_char_slice(environment, args[1]);
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    const state = vm.state orelse return error.ClosedVM;
    var reference: c_int = 0;
    if (lua.kinda_lua_coroutine_create(state, code.ptr, code.len, &reference) != 0) return Error.FailedToEvaluate;
    _ = vm.children.fetchAdd(1, .acq_rel);
    var vm_ref = beam.ResourceRef(VM).init(vm);
    errdefer {
        lua.kinda_lua_coroutine_release(state, reference);
        vm_ref.deinit();
        vm.releaseChild();
    }
    return CoroutineKind.resource.make(environment, .{ .reference = reference, .vm = vm_ref }) catch return error.OutOfMemory;
}

fn resumeCoroutine(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const coroutine = try beam.fetch_resource_ptr(*Coroutine, environment, CoroutineKind.resource.t, args[0]);
    lock(&coroutine.mutex);
    defer coroutine.mutex.unlock();
    if (coroutine.closed) return error.ClosedCoroutine;
    const vm = coroutine.vm.get();
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    const state = vm.state orelse return error.ClosedVM;
    var yielded: c_int = 0;
    var count: c_int = 0;
    if (lua.kinda_lua_coroutine_resume(state, coroutine.reference, &yielded, &count) != 0) return Error.FailedToEvaluate;
    defer lua.kinda_lua_coroutine_clear(state, coroutine.reference);
    const terms = try beam.allocator.alloc(beam.term, @intCast(count));
    defer beam.allocator.free(terms);
    for (terms, 1..) |*term, index| {
        var value: lua.struct_kinda_lua_result = std.mem.zeroes(lua.struct_kinda_lua_result);
        lua.kinda_lua_coroutine_result_at(state, coroutine.reference, @intCast(index), &value);
        term.* = try makeLuaValue(environment, value);
    }
    var response = [_]beam.term{
        beam.make_atom(environment, if (yielded != 0) "yielded" else "done"),
        beam.make_term_list(environment, terms),
    };
    return beam.make_tuple(environment, &response);
}

fn closeCoroutine(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try beam.fetch_resource_ptr(*Coroutine, environment, CoroutineKind.resource.t, args[0])).close();
    return beam.make_ok(environment);
}

fn compileBytecode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const code = try beam.get_char_slice(environment, args[0]);
    var compiled: [*c]u8 = null;
    var size: usize = 0;
    if (lua.kinda_lua_compile(code.ptr, code.len, &compiled, &size) != 0 or compiled == null) return error.FailedToCompile;
    defer lua.kinda_lua_free(compiled);
    const signature = "Lua 5.4.8\x00";
    const bytes = try beam.allocator.alloc(u8, signature.len + size);
    errdefer beam.allocator.free(bytes);
    @memcpy(bytes[0..signature.len], signature);
    @memcpy(bytes[signature.len..], compiled[0..size]);
    return BytecodeKind.resource.make(environment, .{ .bytes = bytes }) catch return error.OutOfMemory;
}

fn runBytecode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const vm = try beam.fetch_resource_ptr(*VM, environment, VMKind.resource.t, args[0]);
    if (vm.close_requested.load(.acquire)) return error.ClosedVM;
    const bytecode = try beam.fetch_resource_ptr(*Bytecode, environment, BytecodeKind.resource.t, args[1]);
    lock(&bytecode.mutex);
    defer bytecode.mutex.unlock();
    if (bytecode.closed) return error.ClosedBytecode;
    const signature = "Lua 5.4.8\x00";
    if (bytecode.bytes.len < signature.len or !std.mem.eql(u8, bytecode.bytes[0..signature.len], signature)) return error.IncompatibleBytecode;
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    const state = vm.state orelse return error.ClosedVM;
    var count: c_int = 0;
    const payload = bytecode.bytes[signature.len..];
    if (lua.kinda_lua_run_bytecode(state, payload.ptr, payload.len, &count) != 0) return Error.FailedToEvaluate;
    defer lua.kinda_lua_clear_stack(state);
    const terms = try beam.allocator.alloc(beam.term, @intCast(count));
    defer beam.allocator.free(terms);
    for (terms, 1..) |*term, index| {
        var value: lua.struct_kinda_lua_result = std.mem.zeroes(lua.struct_kinda_lua_result);
        lua.kinda_lua_result_at(state, @intCast(index), &value);
        term.* = try makeLuaValue(environment, value);
    }
    return beam.make_term_list(environment, terms);
}

fn closeBytecode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try beam.fetch_resource_ptr(*Bytecode, environment, BytecodeKind.resource.t, args[0])).close();
    return beam.make_ok(environment);
}

fn createUserdata(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const vm = try beam.fetch_resource_ptr(*VM, environment, VMKind.resource.t, args[0]);
    if (vm.close_requested.load(.acquire)) return error.ClosedVM;
    const value = try beam.get_i64(environment, args[1]);
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    const state = vm.state orelse return error.ClosedVM;
    var reference: c_int = 0;
    if (lua.kinda_lua_userdata_create(state, value, &reference) != 0) return error.OutOfMemory;
    _ = vm.children.fetchAdd(1, .acq_rel);
    var vm_ref = beam.ResourceRef(VM).init(vm);
    errdefer {
        lua.kinda_lua_userdata_release(state, reference);
        vm_ref.deinit();
        vm.releaseChild();
    }
    return UserdataKind.resource.make(environment, .{ .reference = reference, .vm = vm_ref }) catch return error.OutOfMemory;
}

fn userdataValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const userdata = try beam.fetch_resource_ptr(*Userdata, environment, UserdataKind.resource.t, args[0]);
    lock(&userdata.mutex);
    defer userdata.mutex.unlock();
    if (userdata.closed) return error.ClosedUserdata;
    const vm = userdata.vm.get();
    lock(&vm.mutex);
    defer vm.mutex.unlock();
    const state = vm.state orelse return error.ClosedVM;
    return beam.make_i64(environment, lua.kinda_lua_userdata_value(state, userdata.reference));
}

fn closeUserdata(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try beam.fetch_resource_ptr(*Userdata, environment, UserdataKind.resource.t, args[0])).close();
    return beam.make_ok(environment);
}

fn version(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_slice(environment, std.mem.span(lua.kinda_lua_version()));
}

const all_nifs = .{
    result.nif("version", 0, version).entry,
    result.nif_with_flags("eval", 1, eval, cpu_bound).entry,
    result.nif_with_flags("create_vm", 1, createVM, cpu_bound).entry,
    result.nif_with_flags("eval_vm", 2, evalVM, cpu_bound).entry,
    result.nif_with_flags("close_vm", 1, closeVM, cpu_bound).entry,
    result.nif_with_flags("allocator_stats", 1, allocatorStats, cpu_bound).entry,
    result.nif_with_flags("create_coroutine", 2, createCoroutine, cpu_bound).entry,
    result.nif_with_flags("resume_coroutine", 1, resumeCoroutine, cpu_bound).entry,
    result.nif_with_flags("close_coroutine", 1, closeCoroutine, cpu_bound).entry,
    result.nif_with_flags("compile_bytecode", 1, compileBytecode, cpu_bound).entry,
    result.nif_with_flags("run_bytecode", 2, runBytecode, cpu_bound).entry,
    result.nif_with_flags("close_bytecode", 1, closeBytecode, cpu_bound).entry,
    result.nif_with_flags("create_userdata", 2, createUserdata, cpu_bound).entry,
    result.nif_with_flags("userdata_value", 1, userdataValue, cpu_bound).entry,
    result.nif_with_flags("close_userdata", 1, closeUserdata, cpu_bound).entry,
};
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

fn nifLoad(environment: beam.env, _: [*c]?*anyopaque, _: beam.term) callconv(.c) c_int {
    VMKind.open(environment);
    CoroutineKind.open(environment);
    BytecodeKind.open(environment);
    UserdataKind.open(environment);
    return if (VMKind.resource.t == null or CoroutineKind.resource.t == null or BytecodeKind.resource.t == null or UserdataKind.resource.t == null) 1 else 0;
}

fn nifUpgrade(environment: beam.env, private_data: [*c]?*anyopaque, _: [*c]?*anyopaque, load_info: beam.term) callconv(.c) c_int {
    return nifLoad(environment, private_data, load_info);
}

const entry = e.ErlNifEntry{ .major = 2, .minor = 16, .name = root_module, .num_of_funcs = nifs.len, .funcs = &(nifs[0]), .load = nifLoad, .reload = null, .upgrade = nifUpgrade, .unload = null, .vm_variant = "beam.vanilla", .options = 1, .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit), .min_erts = "erts-15.0" };

const NifInit = if (builtin.os.tag == .windows) struct {
    var callbacks: e.TWinDynNifCallbacks = undefined;
    fn init(win_callbacks: *const e.TWinDynNifCallbacks) callconv(.c) *const e.ErlNifEntry { callbacks = win_callbacks.*; return &entry; }
    fn exportSymbols() void { @export(&callbacks, .{ .name = "WinDynNifCallbacks" }); @export(&init, .{ .name = "nif_init" }); }
} else struct {
    fn init() callconv(.c) *const e.ErlNifEntry { return &entry; }
    fn exportSymbols() void { @export(&init, .{ .name = "nif_init" }); }
};
comptime { NifInit.exportSymbols(); }
