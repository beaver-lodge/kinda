const kinda = @import("kinda");

fn invalid(_: kinda.beam.env) !kinda.beam.term {
    return error.Unreachable;
}

comptime {
    _ = kinda.result.nif("invalid", 0, invalid);
}
