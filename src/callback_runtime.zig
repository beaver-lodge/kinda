//! Runtime support for synchronous callbacks from native worker threads into
//! BEAM processes.
//!
//! Native libraries keep their domain-specific callback signatures and term
//! conversion. `Dispatcher` owns the callback terms, sends callback messages,
//! waits without occupying a BEAM scheduler, and transfers callback ownership
//! to the process that replies. `ReplyToken` is the consumer-loaded NIF
//! resource used to complete an invocation.

const std = @import("std");
const builtin = @import("builtin");
const kinda = @import("kinda.zig");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;
const windows = std.os.windows;

const INFINITE: u32 = 0xffff_ffff;

extern "kernel32" fn AcquireSRWLockExclusive(srwlock: *windows.SRWLOCK) void;
extern "kernel32" fn ReleaseSRWLockExclusive(srwlock: *windows.SRWLOCK) void;
extern "kernel32" fn SleepConditionVariableSRW(
    cond: *windows.CONDITION_VARIABLE,
    srwlock: *windows.SRWLOCK,
    timeout_ms: u32,
    flags: u32,
) windows.BOOL;
extern "kernel32" fn WakeConditionVariable(cond: *windows.CONDITION_VARIABLE) void;
extern "kernel32" fn GetTickCount64() u64;

const Mutex = if (builtin.os.tag == .windows)
    struct {
        srw: windows.SRWLOCK = .{},
    }
else
    std.c.pthread_mutex_t;

const Condition = if (builtin.os.tag == .windows)
    struct {
        cond: windows.CONDITION_VARIABLE = .{},
    }
else
    std.c.pthread_cond_t;

pub const Response = struct {
    success: bool,
    skipped: bool = false,
    status: Status = .replied,
    code: i64 = 0,
    projection: usize = 0,

    pub const Status = enum {
        replied,
        canceled,
        dropped,
        timed_out,
    };
};

pub const Error = error{
    CallbackOnSchedulerThread,
    FailedToAllocateEnvironment,
    FailedToAllocateLibraryPin,
    FailedToAllocateReplyToken,
    FailedToSendCallback,
};

/// Pins the native library generation which created a Dispatcher.
///
/// Resource-type takeover is correct for data-only resources, but a native
/// library may retain a callback function pointer into the old DSO. The
/// address-qualified resource type below is only taken over when the exact
/// same DSO is shared; otherwise its live objects postpone unloading until all
/// dispatchers from that generation are destroyed.
const LibraryPin = struct {
    var resource_type: beam.resource_type = undefined;

    fn destroy(_: beam.env, _: ?*anyopaque) callconv(.c) void {}

    fn open(environment: beam.env) void {
        var name_buffer: [128]u8 = undefined;
        const name = std.fmt.bufPrintZ(
            &name_buffer,
            "Kinda.CallbackRuntime.LibraryPin.{x}",
            .{@intFromPtr(&destroy)},
        ) catch @panic("failed to format callback runtime library pin name");
        resource_type = e.enif_open_resource_type(
            environment,
            null,
            name.ptr,
            destroy,
            e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER,
            null,
        );
        if (resource_type == null) @panic("failed to open callback runtime library pin type");
    }

    fn acquire() Error!*anyopaque {
        return e.enif_alloc_resource(resource_type, 1) orelse
            Error.FailedToAllocateLibraryPin;
    }

    fn release(pin: *anyopaque) void {
        e.enif_release_resource(pin);
    }
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
        mutex: Mutex = .{},
        condition: Condition = .{},
        references: std.atomic.Value(usize) = .init(2),
        done: bool = false,
        success: bool = false,
        status: Response.Status = .dropped,
        code: i64 = 0,
        projection: usize = 0,
        caller: ?beam.pid = null,

        const Snapshot = struct {
            success: bool,
            status: Response.Status,
            code: i64,
            projection: usize,
            caller: ?beam.pid,
        };

        fn snapshotLocked(self: *const State) Snapshot {
            return .{
                .success = self.success,
                .status = self.status,
                .code = self.code,
                .projection = self.projection,
                .caller = self.caller,
            };
        }

        fn wait(self: *State, timeout_ms: ?u64) Snapshot {
            self.lock();
            defer self.unlock();

            if (timeout_ms) |milliseconds| {
                if (builtin.os.tag == .windows) {
                    const deadline = std.math.add(u64, GetTickCount64(), milliseconds) catch
                        std.math.maxInt(u64);
                    while (!self.done) {
                        const now = GetTickCount64();
                        const remaining = if (deadline > now) deadline - now else 0;
                        if (remaining == 0) {
                            if (!self.done) self.finishLocked(.timed_out, false, 0, 0, null);
                            break;
                        }
                        const slept = SleepConditionVariableSRW(
                            &self.condition.cond,
                            &self.mutex.srw,
                            @intCast(@min(remaining, std.math.maxInt(u32))),
                            0,
                        );
                        if (slept == .FALSE) {
                            if (!self.done) self.finishLocked(.timed_out, false, 0, 0, null);
                            break;
                        }
                    }
                } else {
                    const deadline = deadlineFromNow(milliseconds);
                    while (!self.done) {
                        switch (std.c.pthread_cond_timedwait(&self.condition, &self.mutex, &deadline)) {
                            .SUCCESS => {},
                            .TIMEDOUT => {
                                if (!self.done) self.finishLocked(.timed_out, false, 0, 0, null);
                            },
                            else => @panic("callback reply condition wait failed"),
                        }
                    }
                }
            } else {
                while (!self.done) {
                    if (builtin.os.tag == .windows) {
                        _ = SleepConditionVariableSRW(
                            &self.condition.cond,
                            &self.mutex.srw,
                            INFINITE,
                            0,
                        );
                    } else {
                        if (std.c.pthread_cond_wait(&self.condition, &self.mutex) != .SUCCESS)
                            @panic("callback reply condition wait failed");
                    }
                }
            }

            return self.snapshotLocked();
        }

        fn complete(
            self: *State,
            status: Response.Status,
            success: bool,
            code: i64,
            projection: usize,
            caller: ?beam.pid,
        ) bool {
            self.lock();
            defer self.unlock();

            if (self.done) return false;
            self.finishLocked(status, success, code, projection, caller);
            if (builtin.os.tag == .windows) {
                WakeConditionVariable(&self.condition.cond);
            } else {
                if (std.c.pthread_cond_signal(&self.condition) != .SUCCESS)
                    @panic("callback reply condition signal failed");
            }
            return true;
        }

        fn finishLocked(
            self: *State,
            status: Response.Status,
            success: bool,
            code: i64,
            projection: usize,
            caller: ?beam.pid,
        ) void {
            self.done = true;
            self.success = success;
            self.status = status;
            self.code = code;
            self.projection = projection;
            self.caller = caller;
        }

        fn release(self: *State) void {
            if (self.references.fetchSub(1, .acq_rel) == 1) {
                if (builtin.os.tag != .windows) {
                    if (std.c.pthread_cond_destroy(&self.condition) != .SUCCESS)
                        @panic("failed to destroy callback reply condition");
                    if (std.c.pthread_mutex_destroy(&self.mutex) != .SUCCESS)
                        @panic("failed to destroy callback reply mutex");
                }
                std.heap.smp_allocator.destroy(self);
            }
        }

        fn lock(self: *State) void {
            if (builtin.os.tag == .windows) {
                AcquireSRWLockExclusive(&self.mutex.srw);
            } else {
                if (std.c.pthread_mutex_lock(&self.mutex) != .SUCCESS)
                    @panic("failed to lock callback reply mutex");
            }
        }

        fn unlock(self: *State) void {
            if (builtin.os.tag == .windows) {
                ReleaseSRWLockExclusive(&self.mutex.srw);
            } else {
                if (std.c.pthread_mutex_unlock(&self.mutex) != .SUCCESS)
                    @panic("failed to unlock callback reply mutex");
            }
        }

        fn deadlineFromNow(milliseconds: u64) std.c.timespec {
            var now: std.c.timeval = undefined;
            if (std.c.gettimeofday(&now, null) != 0)
                @panic("failed to read callback reply deadline clock");

            const nanoseconds = @as(u64, @intCast(now.usec)) * std.time.ns_per_us +
                (milliseconds % std.time.ms_per_s) * std.time.ns_per_ms;
            const seconds_to_add = milliseconds / std.time.ms_per_s +
                nanoseconds / std.time.ns_per_s;
            const max_seconds: u64 = @intCast(std.math.maxInt(std.c.time_t));
            const now_seconds: u64 = @intCast(now.sec);
            const deadline_seconds = std.math.add(u64, now_seconds, seconds_to_add) catch
                max_seconds;

            return .{
                .sec = @intCast(@min(deadline_seconds, max_seconds)),
                .nsec = @intCast(nanoseconds % std.time.ns_per_s),
            };
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
        _ = self.state.complete(.dropped, false, 0, 0, null);
        self.state.release();
    }

    fn reply(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
        const success = try beam.get_bool(environment, args[1]);
        return completeTerm(environment, args[0], .replied, success, 0, 0);
    }

    fn replyCode(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
        return completeTerm(
            environment,
            args[0],
            .replied,
            try beam.get_bool(environment, args[1]),
            try beam.get_i64(environment, args[2]),
            0,
        );
    }

    fn replyProjection(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
        return completeTerm(
            environment,
            args[0],
            .replied,
            try beam.get_bool(environment, args[1]),
            try beam.get_i64(environment, args[2]),
            try beam.get_usize(environment, args[3]),
        );
    }

    fn cancel(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
        return completeTerm(environment, args[0], .canceled, false, 0, 0);
    }

    fn completeTerm(
        environment: beam.env,
        token_term: beam.term,
        status: Response.Status,
        success: bool,
        code: i64,
        projection: usize,
    ) !beam.term {
        const accepted = try complete(
            environment,
            token_term,
            status,
            success,
            code,
            projection,
        );
        return beam.make_atom(environment, if (accepted) "ok" else "stale");
    }

    /// Completes a token after the consumer has validated and projected its
    /// callback-specific return value. Returns false for a canceled, timed
    /// out, dropped, or already-replied token.
    pub fn complete(
        environment: beam.env,
        token_term: beam.term,
        status: Response.Status,
        success: bool,
        code: i64,
        projection: usize,
    ) !bool {
        const token = try beam.fetch_resource_ptr(*ReplyToken, environment, resource_type, token_term);
        return token.state.complete(
            status,
            success,
            code,
            projection,
            try beam.self(environment),
        );
    }

    /// Returns the NIF entry that the consuming native library must export.
    pub fn nif(comptime name: [*c]const u8) e.ErlNifFunc {
        return result.nif(name, 2, reply).entry;
    }

    /// Returns a reply NIF which accepts `(token, success, code)`.
    pub fn codeNif(comptime name: [*c]const u8) e.ErlNifFunc {
        return result.nif(name, 3, replyCode).entry;
    }

    /// Returns a reply NIF which accepts `(token, success, code, projection)`.
    /// `projection` is consumer-owned data, commonly a native handle encoded
    /// as an integer after the consumer has validated its resource type.
    pub fn projectionNif(comptime name: [*c]const u8) e.ErlNifFunc {
        return result.nif(name, 4, replyProjection).entry;
    }

    /// Returns a one-argument NIF that cancels a pending token. Late replies
    /// return `stale` and never mutate the completed invocation.
    pub fn cancelNif(comptime name: [*c]const u8) e.ErlNifFunc {
        return result.nif(name, 1, cancel).entry;
    }

    /// Opens the reply resource type from the consuming library's NIF load
    /// callback.
    pub fn open(environment: beam.env) void {
        LibraryPin.open(environment);
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
        timeout_ms: ?u64 = 30_000,
        library_pin: *anyopaque,
        invoke_mutex: std.Io.Mutex = .init,

        pub const Options = struct {
            /// `null` preserves an intentionally unbounded wait. Consumers
            /// should normally retain the bounded default.
            timeout_ms: ?u64 = 30_000,
        };

        fn callbackIndex(comptime callback_name: []const u8) comptime_int {
            inline for (callback_names, 0..) |candidate, index| {
                if (std.mem.eql(u8, callback_name, candidate)) return index;
            }
            @compileError("unknown callback name: " ++ callback_name);
        }

        pub fn init(handler: beam.pid) !*Self {
            return initWithOptions(handler, .{});
        }

        pub fn initWithOptions(handler: beam.pid, options: Options) !*Self {
            const environment = e.enif_alloc_env() orelse return Error.FailedToAllocateEnvironment;
            errdefer e.enif_free_env(environment);
            return initWithEnvAndOptions(environment, handler, options);
        }

        /// Creates a dispatcher which takes ownership of `owned_env`.
        pub fn initWithEnv(owned_env: beam.env, handler: beam.pid) !*Self {
            return initWithEnvAndOptions(owned_env, handler, .{});
        }

        pub fn initWithEnvAndOptions(owned_env: beam.env, handler: beam.pid, options: Options) !*Self {
            const library_pin = try LibraryPin.acquire();
            errdefer LibraryPin.release(library_pin);
            const self = try std.heap.smp_allocator.create(Self);
            self.* = .{
                .handler = handler,
                .env = owned_env,
                .id = e.enif_make_unique_integer(owned_env, e.ERL_NIF_UNIQUE_POSITIVE),
                .timeout_ms = options.timeout_ms,
                .library_pin = library_pin,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            e.enif_free_env(self.env);
            LibraryPin.release(self.library_pin);
            std.heap.smp_allocator.destroy(self);
        }

        pub fn clone(self: *const Self) !*Self {
            const cloned = try initWithOptions(self.handler, .{ .timeout_ms = self.timeout_ms });
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

            const io = std.Options.debug_io;
            self.invoke_mutex.lockUncancelable(io);
            defer self.invoke_mutex.unlock(io);

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

            const response = allocation.state.wait(self.timeout_ms);
            if (response.status == .replied) {
                if (response.caller) |caller| self.handler = caller;
            }
            return .{
                .success = response.success,
                .status = response.status,
                .code = response.code,
                .projection = response.projection,
            };
        }
    };
}
