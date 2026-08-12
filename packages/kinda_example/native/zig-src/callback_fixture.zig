const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;

const public_module = "Elixir.KindaExample.NIF";
const callback_names = .{ "invoke", "destruct" };
const Dispatcher = kinda.callback_runtime.Dispatcher(callback_names);

pub const Handle = kinda.ResourceKind(c_int, public_module ++ ".CallbackHandle");

var registration_type: beam.resource_type = undefined;
var registrations_created: std.atomic.Value(usize) = .init(0);
var registrations_destroyed: std.atomic.Value(usize) = .init(0);

const Registration = struct {
    dispatcher: *Dispatcher,
    dispatch: *const fn (*Registration, beam.env, i64, bool) anyerror!kinda.callback_runtime.Response,
    closed: std.atomic.Value(bool) = .init(false),

    fn close(self: *Registration) bool {
        if (self.closed.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) return false;
        self.dispatcher.deinit();
        _ = registrations_destroyed.fetchAdd(1, .monotonic);
        return true;
    }
};

fn destroyRegistration(_: beam.env, object: ?*anyopaque) callconv(.c) void {
    const registration: *Registration = @ptrCast(@alignCast(object orelse return));
    _ = registration.close();
}

fn fetchRegistration(environment: beam.env, term: beam.term) !*Registration {
    return beam.fetch_resource_ptr(*Registration, environment, registration_type, term);
}

fn register(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const dispatcher = try Dispatcher.initWithOptions(try beam.self(environment), .{
        .timeout_ms = try beam.get_u64(environment, args[2]),
    });
    errdefer dispatcher.deinit();
    dispatcher.setCallback("invoke", args[0]);
    dispatcher.setCallback("destruct", if (beam.is_nil2(environment, args[1])) null else args[1]);

    const memory = e.enif_alloc_resource(registration_type, @sizeOf(Registration)) orelse
        return error.FailedToAllocateRegistration;
    const registration: *Registration = @ptrCast(@alignCast(memory));
    registration.* = .{
        .dispatcher = dispatcher,
        .dispatch = dispatchRegistration,
    };
    const term = e.enif_make_resource(environment, memory);
    e.enif_release_resource(memory);
    _ = registrations_created.fetchAdd(1, .monotonic);
    return term;
}

fn makeArguments(environment: beam.env, input: i64) !struct { beam.term, beam.term } {
    const value: c_int = @intCast(input);
    const values = [_]c_int{ value, value + 1, value + 2 };
    return .{
        try kinda.callback_adapter.handle(Handle, environment, value),
        try kinda.callback_adapter.handleRange(Handle, environment, &values),
    };
}

fn dispatchRegistration(
    registration: *Registration,
    message_env: beam.env,
    input: i64,
    destruct: bool,
) !kinda.callback_runtime.Response {
    if (destruct) return registration.dispatcher.invoke("destruct", message_env, .{});
    const callback_args = try makeArguments(message_env, input);
    return registration.dispatcher.invoke("invoke", message_env, callback_args);
}

fn invokeOnScheduler(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const registration = try fetchRegistration(environment, args[0]);
    const message_env = e.enif_alloc_env() orelse return error.FailedToAllocateEnvironment;
    const callback_args = try makeArguments(message_env, try beam.get_i64(environment, args[1]));
    const response = registration.dispatcher.invoke("invoke", message_env, callback_args) catch |err| {
        return beam.make_atom(environment, @errorName(err));
    };
    return responseTerm(environment, response);
}

const Worker = struct {
    registration: *Registration,
    recipient: beam.pid,
    input: i64 = 0,
    destruct: bool = false,

    fn send(self: *Worker, message: beam.term, message_env: beam.env) void {
        _ = beam.send_advanced(null, self.recipient, message_env, message);
        e.enif_free_env(message_env);
    }

    fn run(self: *Worker) void {
        const registration = self.registration;
        defer std.heap.smp_allocator.destroy(self);
        defer e.enif_release_resource(registration);

        if (self.registration.closed.load(.acquire)) {
            const message_env = e.enif_alloc_env() orelse return;
            var terms = [_]beam.term{
                beam.make_atom(message_env, "callback_fixture_error"),
                beam.make_atom(message_env, "registration_closed"),
            };
            return self.send(beam.make_tuple(message_env, &terms), message_env);
        }

        const message_env = e.enif_alloc_env() orelse return;
        const response = self.registration.dispatch(
            self.registration,
            message_env,
            self.input,
            self.destruct,
        ) catch |err| {
            const result_env = e.enif_alloc_env() orelse return;
            var terms = [_]beam.term{
                beam.make_atom(result_env, "callback_fixture_error"),
                beam.make_atom(result_env, @errorName(err)),
            };
            return self.send(beam.make_tuple(result_env, &terms), result_env);
        };

        if (self.destruct) _ = self.registration.close();

        const result_env = e.enif_alloc_env() orelse return;
        var terms = [_]beam.term{
            beam.make_atom(result_env, if (self.destruct) "callback_fixture_destroyed" else "callback_fixture_done"),
            beam.make_atom(result_env, @tagName(response.status)),
            beam.make_bool(result_env, response.success),
            beam.make_i64(result_env, response.code),
            beam.make_usize(result_env, response.projection),
        };
        self.send(beam.make_tuple(result_env, &terms), result_env);
    }
};

fn spawnWorker(environment: beam.env, registration: *Registration, input: i64, destruct: bool) !beam.term {
    const worker = try std.heap.smp_allocator.create(Worker);
    errdefer std.heap.smp_allocator.destroy(worker);
    worker.* = .{
        .registration = registration,
        .recipient = try beam.self(environment),
        .input = input,
        .destruct = destruct,
    };
    e.enif_keep_resource(registration);
    errdefer e.enif_release_resource(registration);
    const thread = try std.Thread.spawn(.{}, Worker.run, .{worker});
    thread.detach();
    return beam.make_ok(environment);
}

fn invokeOnWorker(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return spawnWorker(
        environment,
        try fetchRegistration(environment, args[0]),
        try beam.get_i64(environment, args[1]),
        false,
    );
}

fn destroyOnWorker(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return spawnWorker(environment, try fetchRegistration(environment, args[0]), 0, true);
}

fn stats(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    var terms = [_]beam.term{
        beam.make_usize(environment, registrations_created.load(.monotonic)),
        beam.make_usize(environment, registrations_destroyed.load(.monotonic)),
    };
    return beam.make_tuple(environment, &terms);
}

fn responseTerm(environment: beam.env, response: kinda.callback_runtime.Response) beam.term {
    var terms = [_]beam.term{
        beam.make_atom(environment, @tagName(response.status)),
        beam.make_bool(environment, response.success),
        beam.make_i64(environment, kinda.callback_adapter.scalarResult(i64, response, 0)),
        beam.make_usize(environment, response.projection),
    };
    return beam.make_tuple(environment, &terms);
}

pub fn open(environment: beam.env) void {
    registration_type = e.enif_open_resource_type(
        environment,
        null,
        "Kinda.CallbackRuntime.FixtureRegistration",
        destroyRegistration,
        e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER,
        null,
    );
    if (registration_type == null) @panic("failed to open callback fixture registration resource");
    Handle.open_all(environment);
}

pub const nifs = .{
    result.nif("callback_fixture_register", 3, register).entry,
    result.nif("callback_fixture_invoke_on_scheduler", 2, invokeOnScheduler).entry,
    result.nif("callback_fixture_invoke_on_worker", 2, invokeOnWorker).entry,
    result.nif("callback_fixture_destroy_on_worker", 1, destroyOnWorker).entry,
    result.nif("callback_fixture_stats", 0, stats).entry,
    kinda.callback_runtime.ReplyToken.codeNif("callback_fixture_reply_code"),
    kinda.callback_runtime.ReplyToken.projectionNif("callback_fixture_reply_projection"),
    kinda.callback_runtime.ReplyToken.cancelNif("callback_fixture_cancel"),
};
