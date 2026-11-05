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
const nifApi = kinda.nifApi;
const result = kinda.result;
const io = std.Options.debug_io;

pub const Response = struct {
    success: bool,
    skipped: bool = false,
    status: Status = .replied,
    code: i64 = 0,
    projection: usize = 0,

    pub const Status = enum { replied, canceled, dropped, timed_out };
};

pub const Error = error{
    CallbackOnSchedulerThread,
    FailedToAllocateEnvironment,
    FailedToAllocateLibraryPin,
    FailedToAllocateReplyToken,
    FailedToSendCallback,
};

/// Pins the native library generation which created a dispatcher or reply state.
///
/// Resource-type takeover is correct for data-only resources, but a native
/// library may retain a callback function pointer into the old DSO. The
/// address-qualified resource type below is only taken over when the exact
/// same DSO is shared; otherwise its live objects postpone unloading until all
/// dispatchers and reply states from that generation are destroyed.
const LibraryPin = struct {
    var resource_type: beam.resource_type = undefined;

    fn destroy(_: beam.env, _: ?*anyopaque) callconv(.c) void {}

    fn open(environment: beam.env) void {
        var name_buffer: [128]u8 = undefined;
        const name = std.fmt.bufPrintZ(&name_buffer, "Kinda.CallbackRuntime.LibraryPin.{x}", .{@intFromPtr(&destroy)}) catch @panic("failed to format callback runtime library pin name");
        resource_type = beam.open_resource_type(environment, name.ptr, destroy);
        if (resource_type == null) @panic("failed to open callback runtime library pin type");
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
    pub const resource = kinda.RawResourceType(ReplyToken, resource_name, destroy);

    const Allocation = struct { state: *State, term: beam.term };

    const State = struct {
        // Windows futex queues belong to the creating DSO. Keep its backend alive
        // even after resource-type takeover and dispatcher destruction.
        backend: std.Io = io,
        mutex: std.Io.Mutex = .init,
        completed: std.Io.Event = .unset,
        response: Response = .{ .success = false, .status = .dropped },
        caller: ?beam.pid = null,
        const Snapshot = struct { response: Response, caller: ?beam.pid };

        fn wait(self: *State, timeout_ms: ?u64) Snapshot {
            if (timeout_ms) |milliseconds| {
                const duration: std.Io.Timeout = .{ .duration = .{
                    .clock = .awake,
                    .raw = .{ .nanoseconds = @as(i96, milliseconds) * std.time.ns_per_ms },
                } };
                const deadline = duration.toDeadline(self.backend);
                while (!self.completed.isSet()) {
                    self.completed.waitTimeout(self.backend, deadline) catch |err| switch (err) {
                        error.Canceled => @panic("callback reply wait canceled"),
                        // Event waits can wake spuriously: only expire the original deadline.
                        error.Timeout => if (deadline.toDurationFromNow(self.backend).?.raw.toNanoseconds() <= 0) {
                            _ = self.complete(.{ .status = .timed_out, .success = false }, null);
                        },
                    };
                }
            } else self.completed.waitUncancelable(self.backend);
            // Event publication releases the immutable terminal snapshot.
            return .{ .response = self.response, .caller = self.caller };
        }

        fn complete(self: *State, response: Response, caller: ?beam.pid) bool {
            self.mutex.lockUncancelable(self.backend);
            defer self.mutex.unlock(self.backend);
            if (self.completed.isSet()) return false;
            self.response = response;
            self.caller = caller;
            self.completed.set(self.backend);
            return true;
        }

        fn release(self: *State) void {
            nifApi("enif_release_resource")(self);
        }
    };

    fn allocate(environment: beam.env) Error!Allocation {
        const memory = nifApi("enif_alloc_resource")(LibraryPin.resource_type, @sizeOf(State)) orelse return Error.FailedToAllocateReplyToken;
        const state: *State = @ptrCast(@alignCast(memory));
        errdefer state.release();
        state.* = .{};

        const token = resource.alloc() catch return Error.FailedToAllocateReplyToken;
        token.* = .{ .state = state };
        nifApi("enif_keep_resource")(state);
        const term = nifApi("enif_make_resource")(environment, token);
        nifApi("enif_release_resource")(token);
        return .{ .state = state, .term = term };
    }

    fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *ReplyToken = @ptrCast(@alignCast(object orelse return));
        _ = self.state.complete(.{ .status = .dropped, .success = false }, null);
        self.state.release();
    }

    fn Completion(comptime arity: usize) type {
        return struct {
            fn call(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
                const accepted = try complete(environment, args[0], if (arity == 1) .canceled else .replied, if (arity == 1) false else try beam.get_bool(environment, args[1]), if (arity > 2) try beam.get_i64(environment, args[2]) else 0, if (arity > 3) try beam.get_usize(environment, args[3]) else 0);
                return beam.make_atom(environment, if (accepted) "ok" else "stale");
            }
            fn entry(comptime name: [*c]const u8) e.ErlNifFunc {
                return result.nif(name, arity, call).entry;
            }
        };
    }

    /// Completes a token after the consumer has validated and projected its
    /// callback-specific return value. Returns false for a canceled, timed
    /// out, dropped, or already-replied token.
    pub fn complete(environment: beam.env, token_term: beam.term, status: Response.Status, success: bool, code: i64, projection: usize) !bool {
        const token = try resource.fetch(environment, token_term);
        const response: Response = .{ .status = status, .success = success, .code = code, .projection = projection };
        return token.state.complete(response, try beam.self(environment));
    }

    /// Returns the NIF entry that the consuming native library must export.
    pub const nif = Completion(2).entry;

    /// Returns a reply NIF which accepts `(token, success, code)`.
    pub const codeNif = Completion(3).entry;

    /// Returns a reply NIF which accepts `(token, success, code, projection)`.
    /// `projection` is consumer-owned data, commonly a native handle encoded
    /// as an integer after the consumer has validated its resource type.
    pub const projectionNif = Completion(4).entry;

    /// Returns a one-argument NIF that cancels a pending token. Late replies
    /// return `stale` and never mutate the completed invocation.
    pub const cancelNif = Completion(1).entry;

    /// Opens the reply resource type from the consuming library's NIF load
    /// callback.
    pub fn open(environment: beam.env) void {
        LibraryPin.open(environment);
        resource.open(environment);
        // Preserve the public slot consumed by older multi-DSO clients. New
        // clients should register `resource.resource_type` directly.
        resource_type = resource.resource_type;
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
            const environment = nifApi("enif_alloc_env")() orelse return Error.FailedToAllocateEnvironment;
            errdefer nifApi("enif_free_env")(environment);
            return initWithEnvAndOptions(environment, handler, options);
        }

        /// Creates a dispatcher which takes ownership of `owned_env`.
        pub fn initWithEnv(owned_env: beam.env, handler: beam.pid) !*Self {
            return initWithEnvAndOptions(owned_env, handler, .{});
        }

        pub fn initWithEnvAndOptions(owned_env: beam.env, handler: beam.pid, options: Options) !*Self {
            const library_pin = nifApi("enif_alloc_resource")(LibraryPin.resource_type, 1) orelse return Error.FailedToAllocateLibraryPin;
            errdefer nifApi("enif_release_resource")(library_pin);
            const self = try std.heap.smp_allocator.create(Self);
            self.* = .{
                .handler = handler,
                .env = owned_env,
                .id = nifApi("enif_make_unique_integer")(owned_env, e.ERL_NIF_UNIQUE_POSITIVE),
                .timeout_ms = options.timeout_ms,
                .library_pin = library_pin,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            nifApi("enif_free_env")(self.env);
            nifApi("enif_release_resource")(self.library_pin);
            std.heap.smp_allocator.destroy(self);
        }

        pub fn clone(self: *const Self) !*Self {
            const cloned = try initWithOptions(self.handler, .{ .timeout_ms = self.timeout_ms });
            errdefer cloned.deinit();
            inline for (callback_names, 0..) |_, index| {
                if (self.callbacks[index]) |callback| cloned.callbacks[index] = nifApi("enif_make_copy")(cloned.env, callback);
            }
            return cloned;
        }

        pub fn setCallback(self: *Self, comptime callback_name: []const u8, callback: ?beam.term) void {
            self.callbacks[callbackIndex(callback_name)] = if (callback) |value|
                nifApi("enif_make_copy")(self.env, value)
            else
                null;
        }

        pub fn hasCallback(self: *const Self, comptime callback_name: []const u8) bool {
            return self.callbacks[callbackIndex(callback_name)] != null;
        }

        pub fn copyId(self: *const Self, destination_env: beam.env) beam.term {
            return nifApi("enif_make_copy")(destination_env, self.id);
        }

        /// Sends one callback and consumes `message_env`.
        pub fn invoke(self: *Self, comptime callback_name: []const u8, message_env: beam.env, args: anytype) !Response {
            if (nifApi("enif_thread_type")() != e.ERL_NIF_THR_UNDEFINED) {
                nifApi("enif_free_env")(message_env);
                return Error.CallbackOnSchedulerThread;
            }

            self.invoke_mutex.lockUncancelable(io);
            defer self.invoke_mutex.unlock(io);

            const callback = self.callbacks[callbackIndex(callback_name)] orelse {
                nifApi("enif_free_env")(message_env);
                return .{ .success = true, .skipped = true };
            };

            const allocation = ReplyToken.allocate(message_env) catch |err| {
                nifApi("enif_free_env")(message_env);
                return err;
            };
            defer allocation.state.release();

            const argument_count = @typeInfo(@TypeOf(args)).@"struct".fields.len;
            var message_terms: [4 + argument_count]beam.term = undefined;
            message_terms[0] = beam.make_atom(message_env, callback_name);
            message_terms[1] = allocation.term;
            message_terms[2] = nifApi("enif_make_copy")(message_env, callback);
            message_terms[3] = nifApi("enif_make_copy")(message_env, self.id);
            inline for (args, 0..) |arg, index| message_terms[4 + index] = arg;

            const message = beam.make_tuple(message_env, &message_terms);
            if (!beam.send_advanced(null, self.handler, message_env, message)) {
                nifApi("enif_free_env")(message_env);
                return Error.FailedToSendCallback;
            }
            nifApi("enif_free_env")(message_env);

            const completed = allocation.state.wait(self.timeout_ms);
            if (completed.response.status == .replied) {
                if (completed.caller) |caller| self.handler = caller;
            }
            return completed.response;
        }
    };
}
