const builtin = @import("builtin");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;

const platform = if (builtin.os.tag == .windows) @import("unsupported.zig") else @import("posix.zig");
const ProcessResource = kinda.RawResourceType(platform.Process, "Kinda.Sandbox.Native.Process", platform.destroy);

fn spawn(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const process = platform.spawn(environment, args) catch |err| {
        return beam.make_error_atom(environment, @errorName(err));
    };
    return beam.make_ok_term(environment, try ProcessResource.make(environment, process));
}

fn readEvent(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const process = try ProcessResource.fetch(environment, args[0]);
    return platform.readEvent(environment, process);
}

fn terminate(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const process = try ProcessResource.fetch(environment, args[0]);
    const grace_milliseconds = try beam.get_u32(environment, args[1]);
    platform.terminate(process, grace_milliseconds);
    return beam.make_ok(environment);
}

const nifs = .{
    result.nif("spawn", 5, spawn).entry,
    result.nif_with_flags("read_event", 1, readEvent, e.ERL_NIF_DIRTY_JOB_IO_BOUND).entry,
    result.nif_with_flags("terminate", 2, terminate, e.ERL_NIF_DIRTY_JOB_IO_BOUND).entry,
};

const nif_exports = kinda.EntryExports(.{
    .name = "Elixir.Kinda.Sandbox.Native",
    .nifs = nifs,
    .load = nifLoad,
    .min_erts = "erts-15.0",
});

comptime {
    _ = nif_exports;
}

fn nifLoad(environment: beam.env, _: [*c]?*anyopaque, _: beam.term) callconv(.c) c_int {
    ProcessResource.open(environment);
    return 0;
}
