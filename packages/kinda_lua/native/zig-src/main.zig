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

    fn close(self: *VM) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.state) |state| lua.kinda_lua_close(state);
        self.state = null;
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *VM = @ptrCast(@alignCast(object orelse return));
        self.close();
        lua.kinda_lua_allocator_destroy(self.allocator);
    }
};

const VMKind = kinda.ResourceKind(VM, "Elixir.Kinda.Lua.VM");

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
};
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

fn nifLoad(environment: beam.env, _: [*c]?*anyopaque, _: beam.term) callconv(.c) c_int {
    VMKind.open(environment);
    return if (VMKind.resource.t == null) 1 else 0;
}

const entry = e.ErlNifEntry{ .major = 2, .minor = 16, .name = root_module, .num_of_funcs = nifs.len, .funcs = &(nifs[0]), .load = nifLoad, .reload = null, .upgrade = null, .unload = null, .vm_variant = "beam.vanilla", .options = 1, .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit), .min_erts = "erts-15.0" };

const NifInit = if (builtin.os.tag == .windows) struct {
    var callbacks: e.TWinDynNifCallbacks = undefined;
    fn init(win_callbacks: *const e.TWinDynNifCallbacks) callconv(.c) *const e.ErlNifEntry { callbacks = win_callbacks.*; return &entry; }
    fn exportSymbols() void { @export(&callbacks, .{ .name = "WinDynNifCallbacks" }); @export(&init, .{ .name = "nif_init" }); }
} else struct {
    fn init() callconv(.c) *const e.ErlNifEntry { return &entry; }
    fn exportSymbols() void { @export(&init, .{ .name = "nif_init" }); }
};
comptime { NifInit.exportSymbols(); }
