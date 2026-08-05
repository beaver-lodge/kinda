//! Runtime support for synchronous callbacks from native worker threads into
//! BEAM processes.
//!
//! Native libraries keep their domain-specific callback signatures and term
//! conversion. `Dispatcher` owns the callback terms, sends callback messages,
//! waits without occupying a BEAM scheduler, and transfers callback ownership
//! to the process that replies. `ReplyToken` is the consumer-loaded NIF
//! resource used to complete an invocation.

const std = @import("std");
const kinda = @import("kinda.zig");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;

pub const Response = struct {
    success: bool,
    skipped: bool = false,
};

pub const Error = error{
    CallbackOnSchedulerThread,
    FailedToAllocateEnvironment,
    FailedToAllocateReplyToken,
    FailedToSendCallback,
};

/// A resource-backed, one-shot reply channel.
///
/// The native waiter and the BEAM resource share a heap-backed state. If the
/// BEAM drops the message without replying, the resource destructor completes
/// the wait as a failure without leaving a pointer to stack memory behind.
pub const ReplyToken = struct {
    state: *State,

    pub var resource_type: beam.resource_type = undefined;
    pub const resource_name = "Kinda.CallbackRuntime.ReplyToken";

    const Allocation = struct {
        state: *State,
        term: beam.term,
    };

    const State = struct {
        mutex: std.Io.Mutex = .init,
        condition: std.Io.Condition = .init,
        references: std.atomic.Value(usize) = .init(2),
        done: bool = false,
        success: bool = false,
        caller: ?beam.pid = null,

        fn wait(self: *State) struct { success: bool, caller: ?beam.pid } {
            const io = std.Options.debug_io;
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);

            while (!self.done) {
                self.condition.waitUncancelable(io, &self.mutex);
            }
            return .{ .success = self.success, .caller = self.caller };
        }

        fn complete(self: *State, success: bool, caller: ?beam.pid) void {
            const io = std.Options.debug_io;
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);

            if (self.done) return;
            self.done = true;
            self.success = success;
            self.caller = caller;
            self.condition.signal(io);
        }

        fn release(self: *State) void {
            if (self.references.fetchSub(1, .acq_rel) == 1) {
                std.heap.smp_allocator.destroy(self);
            }
        }
    };

    fn allocate(environment: beam.env) Error!Allocation {
        const state = std.heap.smp_allocator.create(State) catch
            return Error.FailedToAllocateReplyToken;
        errdefer std.heap.smp_allocator.destroy(state);
        state.* = .{};

        const memory = e.enif_alloc_resource(resource_type, @sizeOf(ReplyToken)) orelse
            return Error.FailedToAllocateReplyToken;
        const token: *ReplyToken = @ptrCast(@alignCast(memory));
        token.* = .{ .state = state };
        const term = e.enif_make_resource(environment, memory);
        e.enif_release_resource(memory);
        return .{ .state = state, .term = term };
    }

    fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *ReplyToken = @ptrCast(@alignCast(object orelse return));
        self.state.complete(false, null);
        self.state.release();
    }

    fn reply(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
        const token = try beam.fetch_resource_ptr(*ReplyToken, environment, resource_type, args[0]);
        token.state.complete(try beam.get_bool(environment, args[1]), try beam.self(environment));
        return beam.make_ok(environment);
    }

    /// Returns the NIF entry that the consuming native library must export.
    pub fn nif(comptime name: [*c]const u8) e.ErlNifFunc {
        return result.nif(name, 2, reply).entry;
    }

    /// Opens the reply resource type from the consuming library's NIF load
    /// callback.
    pub fn open(environment: beam.env) void {
        resource_type = e.enif_open_resource_type(
            environment,
            null,
            resource_name,
            destroy,
            e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER,
            null,
        );
        if (resource_type == null) @panic("failed to open callback reply resource type");
    }
};

/// Builds a callback dispatcher for a compile-time tuple of callback names.
///
/// Messages retain the existing protocol:
///
///     {callback_name, reply_token, callback_fun, dispatcher_id, ...args}
///
/// A callback must be invoked from a non-scheduler thread because invocation
/// waits for a BEAM process to reply.
pub fn Dispatcher(comptime callback_names: anytype) type {
    const callback_count = @typeInfo(@TypeOf(callback_names)).@"struct".fields.len;

    return struct {
        const Self = @This();

        handler: beam.pid,
        env: beam.env,
        id: beam.term,
        callbacks: [callback_count]?beam.term = [_]?beam.term{null} ** callback_count,

        fn callbackIndex(comptime callback_name: []const u8) comptime_int {
            inline for (callback_names, 0..) |candidate, index| {
                if (std.mem.eql(u8, callback_name, candidate)) return index;
            }
            @compileError("unknown callback name: " ++ callback_name);
        }

        pub fn init(handler: beam.pid) !*Self {
            const environment = e.enif_alloc_env() orelse return Error.FailedToAllocateEnvironment;
            errdefer e.enif_free_env(environment);
            return initWithEnv(environment, handler);
        }

        /// Creates a dispatcher which takes ownership of `owned_env`.
        pub fn initWithEnv(owned_env: beam.env, handler: beam.pid) !*Self {
            const self = try std.heap.smp_allocator.create(Self);
            self.* = .{
                .handler = handler,
                .env = owned_env,
                .id = e.enif_make_unique_integer(owned_env, e.ERL_NIF_UNIQUE_POSITIVE),
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            e.enif_free_env(self.env);
            std.heap.smp_allocator.destroy(self);
        }

        pub fn clone(self: *const Self) !*Self {
            const cloned = try init(self.handler);
            errdefer cloned.deinit();
            inline for (callback_names, 0..) |_, index| {
                if (self.callbacks[index]) |callback| {
                    cloned.callbacks[index] = e.enif_make_copy(cloned.env, callback);
                }
            }
            return cloned;
        }

        pub fn setCallback(self: *Self, comptime callback_name: []const u8, callback: ?beam.term) void {
            self.callbacks[callbackIndex(callback_name)] = if (callback) |value|
                e.enif_make_copy(self.env, value)
            else
                null;
        }

        pub fn hasCallback(self: *const Self, comptime callback_name: []const u8) bool {
            return self.callbacks[callbackIndex(callback_name)] != null;
        }

        pub fn copyId(self: *const Self, destination_env: beam.env) beam.term {
            return e.enif_make_copy(destination_env, self.id);
        }

        /// Sends one callback and consumes `message_env`.
        pub fn invoke(
            self: *Self,
            comptime callback_name: []const u8,
            message_env: beam.env,
            args: anytype,
        ) !Response {
            if (e.enif_thread_type() != e.ERL_NIF_THR_UNDEFINED) {
                e.enif_free_env(message_env);
                return Error.CallbackOnSchedulerThread;
            }

            const callback = self.callbacks[callbackIndex(callback_name)] orelse {
                e.enif_free_env(message_env);
                return .{ .success = true, .skipped = true };
            };

            const allocation = ReplyToken.allocate(message_env) catch |err| {
                e.enif_free_env(message_env);
                return err;
            };
            defer allocation.state.release();

            const argument_count = @typeInfo(@TypeOf(args)).@"struct".fields.len;
            var message_terms: [4 + argument_count]beam.term = undefined;
            message_terms[0] = beam.make_atom(message_env, callback_name);
            message_terms[1] = allocation.term;
            message_terms[2] = e.enif_make_copy(message_env, callback);
            message_terms[3] = e.enif_make_copy(message_env, self.id);
            inline for (args, 0..) |arg, index| {
                message_terms[4 + index] = arg;
            }

            const message = beam.make_tuple(message_env, &message_terms);
            if (!beam.send_advanced(null, self.handler, message_env, message)) {
                e.enif_free_env(message_env);
                return Error.FailedToSendCallback;
            }
            e.enif_free_env(message_env);

            const response = allocation.state.wait();
            if (response.caller) |caller| self.handler = caller;
            return .{ .success = response.success };
        }
    };
}
