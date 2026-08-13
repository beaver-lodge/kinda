const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const result = kinda.result;
const sqlite = @cImport({
    @cInclude("sqlite3.h");
    @cInclude("sqlite_bridge.h");
});

const root_module = "Elixir.Kinda.SQLite.Native";
const io_bound: u32 = 2;

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

var databases_created: std.atomic.Value(usize) = .init(0);
var databases_destroyed: std.atomic.Value(usize) = .init(0);
var statements_created: std.atomic.Value(usize) = .init(0);
var statements_destroyed: std.atomic.Value(usize) = .init(0);

const Database = struct {
    pub const PtrType = *Database;

    handle: ?*sqlite.sqlite3,
    mutex: std.atomic.Mutex = .unlocked,

    fn close(self: *Database) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        const handle = self.handle orelse return;
        _ = sqlite.sqlite3_close_v2(handle);
        self.handle = null;
        _ = databases_destroyed.fetchAdd(1, .monotonic);
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Database = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Statement = struct {
    pub const PtrType = *Statement;

    handle: ?*sqlite.sqlite3_stmt,
    database: beam.ResourceRef(Database),
    mutex: std.atomic.Mutex = .unlocked,

    fn finalize(self: *Statement) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        const handle = self.handle orelse return;
        _ = sqlite.sqlite3_finalize(handle);
        self.handle = null;
        self.database.deinit();
        _ = statements_destroyed.fetchAdd(1, .monotonic);
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Statement = @ptrCast(@alignCast(object orelse return));
        self.finalize();
    }
};

const DatabaseKind = kinda.ResourceKind(Database, "Elixir.Kinda.SQLite.Database");
const StatementKind = kinda.ResourceKind(Statement, "Elixir.Kinda.SQLite.Statement");
const ScalarKind = kinda.ResourceKind(c_int, "Elixir.Kinda.SQLite.TestScalar");

const Error = error{
    ClosedDatabase,
    ClosedStatement,
    FailedToOpenDatabase,
    FailedToExecuteSql,
    FailedToPrepareStatement,
    FailedToBindValue,
    FailedToResetStatement,
    FailedToCreateResource,
};

fn fetchDatabase(environment: beam.env, resource: beam.term) !*Database {
    return beam.fetch_resource_ptr(*Database, environment, DatabaseKind.resource.t, resource);
}

fn fetchStatement(environment: beam.env, resource: beam.term) !*Statement {
    return beam.fetch_resource_ptr(*Statement, environment, StatementKind.resource.t, resource);
}

fn databaseHandle(database: *Database) !*sqlite.sqlite3 {
    return database.handle orelse Error.ClosedDatabase;
}

fn statementHandle(statement: *Statement) !*sqlite.sqlite3_stmt {
    return statement.handle orelse Error.ClosedStatement;
}

fn open(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const path = try beam.get_char_slice(environment, args[0]);
    const terminated = try beam.allocator.dupeZ(u8, path);
    defer beam.allocator.free(terminated);

    var handle: ?*sqlite.sqlite3 = null;
    const flags = sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE | sqlite.SQLITE_OPEN_FULLMUTEX;
    if (sqlite.sqlite3_open_v2(terminated.ptr, &handle, flags, null) != sqlite.SQLITE_OK) {
        if (handle) |database| _ = sqlite.sqlite3_close_v2(database);
        return Error.FailedToOpenDatabase;
    }

    const database = handle orelse return Error.FailedToOpenDatabase;
    errdefer _ = sqlite.sqlite3_close_v2(database);
    _ = sqlite.sqlite3_extended_result_codes(database, 1);
    const resource = DatabaseKind.resource.make(environment, .{ .handle = database }) catch
        return Error.FailedToCreateResource;
    _ = databases_created.fetchAdd(1, .monotonic);
    return resource;
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
    _ = sqlite.sqlite3_extended_result_codes(database, 1);
    const resource = DatabaseKind.resource.make(environment, .{ .handle = database }) catch
        return Error.FailedToCreateResource;
    _ = databases_created.fetchAdd(1, .monotonic);
    return resource;
}

fn close(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    database.close();
    return beam.make_ok(environment);
}

fn execute(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    lock(&database.mutex);
    defer database.mutex.unlock();
    const sql = try beam.get_char_slice(environment, args[1]);
    const terminated = try beam.allocator.dupeZ(u8, sql);
    defer beam.allocator.free(terminated);
    var message: [*c]u8 = null;
    const status = sqlite.sqlite3_exec(try databaseHandle(database), terminated.ptr, null, null, &message);
    if (message != null) sqlite.sqlite3_free(message);
    if (status != sqlite.SQLITE_OK) return Error.FailedToExecuteSql;
    return beam.make_ok(environment);
}

fn prepare(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    lock(&database.mutex);
    defer database.mutex.unlock();
    const database_handle = try databaseHandle(database);
    const sql = try beam.get_char_slice(environment, args[1]);
    var handle: ?*sqlite.sqlite3_stmt = null;
    if (sqlite.sqlite3_prepare_v2(database_handle, sql.ptr, @intCast(sql.len), &handle, null) != sqlite.SQLITE_OK) {
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

fn finalize(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    statement.finalize();
    return beam.make_ok(environment);
}

fn reset(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    lock(&statement.mutex);
    defer statement.mutex.unlock();
    if (sqlite.sqlite3_reset(try statementHandle(statement)) != sqlite.SQLITE_OK)
        return Error.FailedToResetStatement;
    return beam.make_ok(environment);
}

fn clearBindings(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    lock(&statement.mutex);
    defer statement.mutex.unlock();
    if (sqlite.sqlite3_clear_bindings(try statementHandle(statement)) != sqlite.SQLITE_OK)
        return Error.FailedToBindValue;
    return beam.make_ok(environment);
}

fn bindNull(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    lock(&statement.mutex);
    defer statement.mutex.unlock();
    if (sqlite.sqlite3_bind_null(try statementHandle(statement), index) != sqlite.SQLITE_OK)
        return Error.FailedToBindValue;
    return beam.make_ok(environment);
}

fn bindInt64(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    const value = try beam.get_i64(environment, args[2]);
    lock(&statement.mutex);
    defer statement.mutex.unlock();
    if (sqlite.sqlite3_bind_int64(try statementHandle(statement), index, value) != sqlite.SQLITE_OK)
        return Error.FailedToBindValue;
    return beam.make_ok(environment);
}

fn bindDouble(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    const value = try beam.get_f64(environment, args[2]);
    lock(&statement.mutex);
    defer statement.mutex.unlock();
    if (sqlite.sqlite3_bind_double(try statementHandle(statement), index, value) != sqlite.SQLITE_OK)
        return Error.FailedToBindValue;
    return beam.make_ok(environment);
}

fn bindText(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return bindBytes(environment, args, false);
}

fn bindBlob(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    return bindBytes(environment, args, true);
}

fn bindBytes(environment: beam.env, args: [*c]const beam.term, blob: bool) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    const value = try beam.get_char_slice(environment, args[2]);
    lock(&statement.mutex);
    defer statement.mutex.unlock();
    const handle = try statementHandle(statement);
    const status = if (blob)
        sqlite.kinda_sqlite_bind_blob_transient(handle, index, value.ptr, @intCast(value.len))
    else
        sqlite.kinda_sqlite_bind_text_transient(handle, index, value.ptr, @intCast(value.len));
    if (status != sqlite.SQLITE_OK) return Error.FailedToBindValue;
    return beam.make_ok(environment);
}

fn step(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    lock(&statement.mutex);
    defer statement.mutex.unlock();
    const database = statement.database.get();
    lock(&database.mutex);
    defer database.mutex.unlock();
    return switch (sqlite.sqlite3_step(try statementHandle(statement))) {
        sqlite.SQLITE_ROW => beam.make_atom(environment, "row"),
        sqlite.SQLITE_DONE => beam.make_atom(environment, "done"),
        else => beam.make_atom(environment, "error"),
    };
}

fn columnCount(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    return beam.make_c_int(environment, sqlite.sqlite3_column_count(try statementHandle(statement)));
}

fn columnName(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    const value = sqlite.sqlite3_column_name(try statementHandle(statement), index) orelse return beam.make_nil(environment);
    return beam.make_slice(environment, std.mem.span(value));
}

fn columnType(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    return switch (sqlite.sqlite3_column_type(try statementHandle(statement), index)) {
        sqlite.SQLITE_INTEGER => beam.make_atom(environment, "integer"),
        sqlite.SQLITE_FLOAT => beam.make_atom(environment, "float"),
        sqlite.SQLITE_TEXT => beam.make_atom(environment, "text"),
        sqlite.SQLITE_BLOB => beam.make_atom(environment, "blob"),
        else => beam.make_atom(environment, "null"),
    };
}

fn columnInt64(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    return beam.make_i64(environment, sqlite.sqlite3_column_int64(try statementHandle(statement), index));
}

fn columnDouble(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    return beam.make_f64(environment, sqlite.sqlite3_column_double(try statementHandle(statement), index));
}

fn columnText(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    const handle = try statementHandle(statement);
    const value = sqlite.sqlite3_column_text(handle, index) orelse return beam.make_nil(environment);
    const size: usize = @intCast(sqlite.sqlite3_column_bytes(handle, index));
    return beam.make_slice(environment, value[0..size]);
}

fn columnBlob(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const statement = try fetchStatement(environment, args[0]);
    const index = try beam.get_c_int(environment, args[1]);
    const handle = try statementHandle(statement);
    const size: usize = @intCast(sqlite.sqlite3_column_bytes(handle, index));
    if (size == 0) return beam.make_slice(environment, &.{});
    const value: [*]const u8 = @ptrCast(sqlite.sqlite3_column_blob(handle, index) orelse return beam.make_nil(environment));
    return beam.make_slice(environment, value[0..size]);
}

fn databaseChanges(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    return beam.make_c_int(environment, sqlite.sqlite3_changes(try databaseHandle(database)));
}

fn lastInsertRowid(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    return beam.make_i64(environment, sqlite.sqlite3_last_insert_rowid(try databaseHandle(database)));
}

fn interrupt(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    sqlite.sqlite3_interrupt(try databaseHandle(database));
    return beam.make_ok(environment);
}

fn errorInfo(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    const handle = try databaseHandle(database);
    var terms = [_]beam.term{
        beam.make_c_int(environment, sqlite.sqlite3_errcode(handle)),
        beam.make_c_int(environment, sqlite.sqlite3_extended_errcode(handle)),
        beam.make_slice(environment, std.mem.span(sqlite.sqlite3_errmsg(handle))),
    };
    return beam.make_tuple(environment, &terms);
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
    result.nif_with_flags("open", 1, open, io_bound).entry,
    result.nif_with_flags("open_memory", 0, openMemory, io_bound).entry,
    result.nif("close", 1, close).entry,
    result.nif_with_flags("execute", 2, execute, io_bound).entry,
    result.nif_with_flags("prepare", 2, prepare, io_bound).entry,
    result.nif("finalize", 1, finalize).entry,
    result.nif("reset", 1, reset).entry,
    result.nif("clear_bindings", 1, clearBindings).entry,
    result.nif("bind_null", 2, bindNull).entry,
    result.nif("bind_int64", 3, bindInt64).entry,
    result.nif("bind_double", 3, bindDouble).entry,
    result.nif("bind_text", 3, bindText).entry,
    result.nif("bind_blob", 3, bindBlob).entry,
    result.nif_with_flags("step", 1, step, io_bound).entry,
    result.nif("column_count", 1, columnCount).entry,
    result.nif("column_name", 2, columnName).entry,
    result.nif("column_type", 2, columnType).entry,
    result.nif("column_int64", 2, columnInt64).entry,
    result.nif("column_double", 2, columnDouble).entry,
    result.nif("column_text", 2, columnText).entry,
    result.nif("column_blob", 2, columnBlob).entry,
    result.nif("database_changes", 1, databaseChanges).entry,
    result.nif("last_insert_rowid", 1, lastInsertRowid).entry,
    result.nif("interrupt", 1, interrupt).entry,
    result.nif("error_info", 1, errorInfo).entry,
    result.nif("sqlite_version", 0, sqliteVersion).entry,
    result.nif("lifecycle_stats", 0, lifecycleStats).entry,
    result.nif("scalar_make", 1, scalarMake).entry,
    result.nif("scalar_value", 1, scalarValue).entry,
};

const Resources = kinda.ResourceRegistry(.{
    kinda.ResourceRegistration{ .kind = DatabaseKind },
    kinda.ResourceRegistration{ .kind = StatementKind },
    kinda.ResourceRegistration{ .kind = ScalarKind },
});

const nif_exports = kinda.EntryExports(.{
    .name = root_module,
    .nifs = all_nifs,
    .load = nif_load,
    .upgrade = nif_upgrade,
    .unload = nif_unload,
});

comptime {
    _ = nif_exports;
}

export fn nif_load(environment: beam.env, _: [*c]?*anyopaque, _: beam.term) c_int {
    return Resources.open(environment);
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
