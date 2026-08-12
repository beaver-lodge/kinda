const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

const root_module = "Elixir.KindaSqliteExample.NIF.Raw";

var databases_created: std.atomic.Value(usize) = .init(0);
var databases_destroyed: std.atomic.Value(usize) = .init(0);
var statements_created: std.atomic.Value(usize) = .init(0);
var statements_destroyed: std.atomic.Value(usize) = .init(0);

const Database = struct {
    pub const PtrType = *Database;

    handle: *sqlite.sqlite3,

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Database = @ptrCast(@alignCast(object orelse return));
        _ = sqlite.sqlite3_close_v2(self.handle);
        _ = databases_destroyed.fetchAdd(1, .monotonic);
    }
};

const Statement = struct {
    pub const PtrType = *Statement;

    handle: *sqlite.sqlite3_stmt,
    database: beam.ResourceRef(Database),

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Statement = @ptrCast(@alignCast(object orelse return));
        _ = sqlite.sqlite3_finalize(self.handle);
        _ = statements_destroyed.fetchAdd(1, .monotonic);
        self.database.deinit();
    }
};

const DatabaseKind = kinda.ResourceKind(Database, "Elixir.KindaSqliteExample.Database");
const StatementKind = kinda.ResourceKind(Statement, "Elixir.KindaSqliteExample.Statement");
const ScalarKind = kinda.ResourceKind(c_int, "Elixir.KindaSqliteExample.Scalar");

const Error = error{
    FailedToOpenDatabase,
    FailedToExecuteSql,
    FailedToPrepareStatement,
    FailedToBindValue,
    FailedToStepStatement,
    FailedToCreateResource,
};

fn fetchDatabase(environment: beam.env, resource: beam.term) !*Database {
    return beam.fetch_resource_ptr(*Database, environment, DatabaseKind.resource.t, resource);
}

fn fetchStatement(environment: beam.env, resource: beam.term) !*Statement {
    return beam.fetch_resource_ptr(*Statement, environment, StatementKind.resource.t, resource);
}

fn openMemory(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    var handle: ?*sqlite.sqlite3 = null;
    const flags = sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE | sqlite.SQLITE_OPEN_FULLMUTEX;
    if (sqlite.sqlite3_open_v2(":memory:", &handle, flags, null) != sqlite.SQLITE_OK) {
        if (handle) |database| _ = sqlite.sqlite3_close_v2(database);
        return Error.FailedToOpenDatabase;
    }

    const database = handle orelse return Error.FailedToOpenDatabase;
    errdefer _ = sqlite.sqlite3_close_v2(database);
    const resource = DatabaseKind.resource.make(environment, .{ .handle = database }) catch
        return Error.FailedToCreateResource;
    _ = databases_created.fetchAdd(1, .monotonic);
    return resource;
}

fn execute(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    const sql = try beam.get_char_slice(environment, args[1]);
    const terminated = try beam.allocator.dupeZ(u8, sql);
    defer beam.allocator.free(terminated);

    var message: [*c]u8 = null;
    const status = sqlite.sqlite3_exec(database.handle, terminated.ptr, null, null, &message);
    if (message != null) sqlite.sqlite3_free(message);
    if (status != sqlite.SQLITE_OK) return Error.FailedToExecuteSql;
    return beam.make_ok(environment);
}

fn prepare(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    const sql = try beam.get_char_slice(environment, args[1]);
    var handle: ?*sqlite.sqlite3_stmt = null;
    if (sqlite.sqlite3_prepare_v2(
        database.handle,
        sql.ptr,
        @intCast(sql.len),
        &handle,
        null,
    ) != sqlite.SQLITE_OK) {
        if (handle) |statement| _ = sqlite.sqlite3_finalize(statement);
        return Error.FailedToPrepareStatement;
    }

    const statement = handle orelse return Error.FailedToPrepareStatement;
    errdefer _ = sqlite.sqlite3_finalize(statement);
    var database_ref = beam.ResourceRef(Database).init(database);
    errdefer database_ref.deinit();
    const resource = StatementKind.resource.make(environment, .{
        .handle = statement,
        .database = database_ref,
    }) catch return Error.FailedToCreateResource;
    database_ref.resource = null;
    _ = statements_created.fetchAdd(1, .monotonic);
    return resource;
}

fn bindInt64(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    const value = try beam.get_i64(environment, args[2]);
    if (sqlite.sqlite3_bind_int64(statement.handle, index, value) != sqlite.SQLITE_OK)
        return Error.FailedToBindValue;
    return beam.make_ok(environment);
}

fn bindText(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    const value = try beam.get_char_slice(environment, args[2]);
    const transient: sqlite.sqlite3_destructor_type = @ptrFromInt(std.math.maxInt(usize));
    if (sqlite.sqlite3_bind_text(
        statement.handle,
        index,
        value.ptr,
        @intCast(value.len),
        transient,
    ) != sqlite.SQLITE_OK) return Error.FailedToBindValue;
    return beam.make_ok(environment);
}

fn step(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    return switch (sqlite.sqlite3_step(statement.handle)) {
        sqlite.SQLITE_ROW => beam.make_atom(environment, "row"),
        sqlite.SQLITE_DONE => beam.make_atom(environment, "done"),
        else => Error.FailedToStepStatement,
    };
}

fn columnInt64(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    return beam.make_i64(environment, sqlite.sqlite3_column_int64(statement.handle, index));
}

fn columnText(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    const value = sqlite.sqlite3_column_text(statement.handle, index) orelse
        return beam.make_nil(environment);
    const size: usize = @intCast(sqlite.sqlite3_column_bytes(statement.handle, index));
    return beam.make_slice(environment, value[0..size]);
}

fn databaseChanges(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    return beam.make_c_int(environment, sqlite.sqlite3_changes(database.handle));
}

fn sqliteVersion(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_slice(environment, std.mem.span(sqlite.sqlite3_libversion()));
}

fn lifecycleStats(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    var terms = [_]beam.term{
        beam.make_usize(environment, databases_created.load(.monotonic)),
        beam.make_usize(environment, databases_destroyed.load(.monotonic)),
        beam.make_usize(environment, statements_created.load(.monotonic)),
        beam.make_usize(environment, statements_destroyed.load(.monotonic)),
    };
    return beam.make_tuple(environment, &terms);
}

fn scalarMake(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return ScalarKind.resource.make(environment, try beam.get_c_int(environment, args[0]));
}

fn scalarValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return beam.make_c_int(environment, try ScalarKind.resource.fetch(environment, args[0]));
}

const all_nifs = .{
    result.nif("open_memory", 0, openMemory).entry,
    result.nif("execute", 2, execute).entry,
    result.nif("prepare", 2, prepare).entry,
    result.nif("bind_int64", 3, bindInt64).entry,
    result.nif("bind_text", 3, bindText).entry,
    result.nif("step", 1, step).entry,
    result.nif("column_int64", 2, columnInt64).entry,
    result.nif("column_text", 2, columnText).entry,
    result.nif("database_changes", 1, databaseChanges).entry,
    result.nif("sqlite_version", 0, sqliteVersion).entry,
    result.nif("lifecycle_stats", 0, lifecycleStats).entry,
    result.nif("scalar_make", 1, scalarMake).entry,
    result.nif("scalar_value", 1, scalarValue).entry,
};
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

const entry = e.ErlNifEntry{
    .major = 2,
    .minor = 16,
    .name = root_module,
    .num_of_funcs = nifs.len,
    .funcs = &(nifs[0]),
    .load = nif_load,
    .reload = null,
    .upgrade = nif_upgrade,
    .unload = nif_unload,
    .vm_variant = "beam.vanilla",
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit),
    .min_erts = "erts-13.0",
};

export fn nif_load(environment: beam.env, _: [*c]?*anyopaque, _: beam.term) c_int {
    DatabaseKind.open(environment);
    StatementKind.open(environment);
    ScalarKind.open(environment);
    if (DatabaseKind.resource.t == null or StatementKind.resource.t == null or ScalarKind.resource.t == null)
        return 1;
    return 0;
}

export fn nif_upgrade(
    environment: beam.env,
    private_data: [*c]?*anyopaque,
    _: [*c]?*anyopaque,
    load_info: beam.term,
) c_int {
    return nif_load(environment, private_data, load_info);
}

export fn nif_unload(_: beam.env, _: ?*anyopaque) void {}

export fn nif_init() *const e.ErlNifEntry {
    return &entry;
}
