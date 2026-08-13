const std = @import("std");
const kinda = @import("kinda");
const beam = kinda.beam;
const result = kinda.result;
const duckdb = @cImport({
    @cInclude("duckdb.h");
});

const root_module = "Elixir.Kinda.DuckDB.Native";
const io_bound: u32 = 2;

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.atomic.spinLoopHint();
}

const Database = struct {
    pub const PtrType = *Database;
    handle: duckdb.duckdb_database,
    mutex: std.atomic.Mutex = .unlocked,
    children: std.atomic.Value(usize) = .init(0),
    close_requested: std.atomic.Value(bool) = .init(false),

    fn close(self: *Database) void {
        self.close_requested.store(true, .release);
        self.closeIfUnused();
    }

    fn closeIfUnused(self: *Database) void {
        if (!self.close_requested.load(.acquire) or self.children.load(.acquire) != 0) return;
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.children.load(.acquire) != 0) return;
        if (self.handle == null) return;
        duckdb.duckdb_close(&self.handle);
    }

    fn releaseChild(self: *Database) void {
        _ = self.children.fetchSub(1, .acq_rel);
        self.closeIfUnused();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Database = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Connection = struct {
    pub const PtrType = *Connection;
    handle: duckdb.duckdb_connection,
    database: beam.ResourceRef(Database),
    mutex: std.atomic.Mutex = .unlocked,
    children: std.atomic.Value(usize) = .init(0),
    close_requested: std.atomic.Value(bool) = .init(false),

    fn close(self: *Connection) void {
        self.close_requested.store(true, .release);
        self.closeIfUnused();
    }

    fn closeIfUnused(self: *Connection) void {
        if (!self.close_requested.load(.acquire) or self.children.load(.acquire) != 0) return;
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.children.load(.acquire) != 0) return;
        if (self.handle == null) return;
        duckdb.duckdb_disconnect(&self.handle);
        self.database.get().releaseChild();
        self.database.deinit();
    }

    fn releaseChild(self: *Connection) void {
        _ = self.children.fetchSub(1, .acq_rel);
        self.closeIfUnused();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Connection = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const QueryResult = struct {
    pub const PtrType = *QueryResult;
    value: duckdb.duckdb_result,
    alive: bool = true,
    connection: beam.ResourceRef(Connection),
    mutex: std.atomic.Mutex = .unlocked,

    fn close(self: *QueryResult) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (!self.alive) return;
        duckdb.duckdb_destroy_result(&self.value);
        self.alive = false;
        self.connection.get().releaseChild();
        self.connection.deinit();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *QueryResult = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Prepared = struct {
    pub const PtrType = *Prepared;
    handle: duckdb.duckdb_prepared_statement,
    connection: beam.ResourceRef(Connection),
    mutex: std.atomic.Mutex = .unlocked,
    children: std.atomic.Value(usize) = .init(0),
    close_requested: std.atomic.Value(bool) = .init(false),

    fn close(self: *Prepared) void {
        self.close_requested.store(true, .release);
        self.closeIfUnused();
    }

    fn closeIfUnused(self: *Prepared) void {
        if (!self.close_requested.load(.acquire) or self.children.load(.acquire) != 0) return;
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.children.load(.acquire) != 0 or self.handle == null) return;
        duckdb.duckdb_destroy_prepare(&self.handle);
        self.connection.get().releaseChild();
        self.connection.deinit();
    }

    fn releaseChild(self: *Prepared) void {
        _ = self.children.fetchSub(1, .acq_rel);
        self.closeIfUnused();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Prepared = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Pending = struct {
    pub const PtrType = *Pending;
    handle: duckdb.duckdb_pending_result,
    prepared: beam.ResourceRef(Prepared),
    mutex: std.atomic.Mutex = .unlocked,

    fn close(self: *Pending) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.handle == null) return;
        duckdb.duckdb_destroy_pending(&self.handle);
        self.prepared.get().releaseChild();
        self.prepared.deinit();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Pending = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const Appender = struct {
    pub const PtrType = *Appender;
    handle: duckdb.duckdb_appender,
    connection: beam.ResourceRef(Connection),
    mutex: std.atomic.Mutex = .unlocked,

    fn close(self: *Appender) void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.handle == null) return;
        _ = duckdb.duckdb_appender_close(self.handle);
        _ = duckdb.duckdb_appender_destroy(&self.handle);
        self.connection.get().releaseChild();
        self.connection.deinit();
    }

    pub fn destroy(_: beam.env, object: ?*anyopaque) callconv(.c) void {
        const self: *Appender = @ptrCast(@alignCast(object orelse return));
        self.close();
    }
};

const DatabaseKind = kinda.ResourceKind(Database, "Elixir.Kinda.DuckDB.Database");
const ConnectionKind = kinda.ResourceKind(Connection, "Elixir.Kinda.DuckDB.Connection");
const ResultKind = kinda.ResourceKind(QueryResult, "Elixir.Kinda.DuckDB.BorrowedResult");
const AppenderKind = kinda.ResourceKind(Appender, "Elixir.Kinda.DuckDB.Appender");
const PreparedKind = kinda.ResourceKind(Prepared, "Elixir.Kinda.DuckDB.Prepared");
const PendingKind = kinda.ResourceKind(Pending, "Elixir.Kinda.DuckDB.Pending");

const Error = error{
    ClosedConnection,
    ClosedResult,
    ClosedAppender,
    FailedToOpenDatabase,
    FailedToConnect,
    FailedToQuery,
    FailedToCreateAppender,
    FailedToAppend,
    FailedToFlushAppender,
    FailedToCreateResource,
    InvalidIndex,
    ClosedPrepared,
    ClosedPending,
    FailedToPrepare,
    FailedToBind,
    FailedToCreatePending,
    PendingNotReady,
};

fn fetchDatabase(environment: beam.env, term: beam.term) !*Database {
    return beam.fetch_resource_ptr(*Database, environment, DatabaseKind.resource.t, term);
}

fn fetchConnection(environment: beam.env, term: beam.term) !*Connection {
    return beam.fetch_resource_ptr(*Connection, environment, ConnectionKind.resource.t, term);
}

fn fetchResult(environment: beam.env, term: beam.term) !*QueryResult {
    return beam.fetch_resource_ptr(*QueryResult, environment, ResultKind.resource.t, term);
}

fn fetchAppender(environment: beam.env, term: beam.term) !*Appender {
    return beam.fetch_resource_ptr(*Appender, environment, AppenderKind.resource.t, term);
}

fn fetchPrepared(environment: beam.env, term: beam.term) !*Prepared {
    return beam.fetch_resource_ptr(*Prepared, environment, PreparedKind.resource.t, term);
}

fn fetchPending(environment: beam.env, term: beam.term) !*Pending {
    return beam.fetch_resource_ptr(*Pending, environment, PendingKind.resource.t, term);
}

fn getTuple(environment: beam.env, term: beam.term) ![]const beam.term {
    var length: c_int = 0;
    var terms: [*c]const beam.term = null;
    if (kinda.nifApi("enif_get_tuple")(environment, term, &length, &terms) == 0)
        return Error.FailedToAppend;
    return terms[0..@intCast(length)];
}

fn libraryVersion(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_slice(environment, std.mem.span(duckdb.duckdb_library_version()));
}

fn open(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const path = try beam.get_char_slice(environment, args[0]);
    const terminated = try beam.allocator.dupeZ(u8, path);
    defer beam.allocator.free(terminated);
    var handle: duckdb.duckdb_database = null;
    if (duckdb.duckdb_open(terminated.ptr, &handle) != duckdb.DuckDBSuccess)
        return Error.FailedToOpenDatabase;
    errdefer duckdb.duckdb_close(&handle);
    return DatabaseKind.resource.make(environment, .{ .handle = handle }) catch
        return Error.FailedToCreateResource;
}

fn closeDatabase(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchDatabase(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn connect(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const database = try fetchDatabase(environment, args[0]);
    if (database.close_requested.load(.acquire)) return Error.FailedToConnect;
    lock(&database.mutex);
    defer database.mutex.unlock();
    var handle: duckdb.duckdb_connection = null;
    if (database.handle == null or duckdb.duckdb_connect(database.handle, &handle) != duckdb.DuckDBSuccess)
        return Error.FailedToConnect;
    errdefer duckdb.duckdb_disconnect(&handle);
    _ = database.children.fetchAdd(1, .acq_rel);
    errdefer database.releaseChild();
    var database_ref = beam.ResourceRef(Database).init(database);
    errdefer database_ref.deinit();
    const resource = ConnectionKind.resource.make(environment, .{
        .handle = handle,
        .database = database_ref,
    }) catch return Error.FailedToCreateResource;
    database_ref.resource = null;
    return resource;
}

fn closeConnection(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchConnection(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn query(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const connection = try fetchConnection(environment, args[0]);
    if (connection.close_requested.load(.acquire)) return Error.ClosedConnection;
    const sql = try beam.get_char_slice(environment, args[1]);
    const terminated = try beam.allocator.dupeZ(u8, sql);
    defer beam.allocator.free(terminated);
    lock(&connection.mutex);
    defer connection.mutex.unlock();
    if (connection.handle == null) return Error.ClosedConnection;
    var query_result: duckdb.duckdb_result = std.mem.zeroes(duckdb.duckdb_result);
    if (duckdb.duckdb_query(connection.handle, terminated.ptr, &query_result) != duckdb.DuckDBSuccess) {
        duckdb.duckdb_destroy_result(&query_result);
        return Error.FailedToQuery;
    }
    errdefer duckdb.duckdb_destroy_result(&query_result);
    _ = connection.children.fetchAdd(1, .acq_rel);
    errdefer connection.releaseChild();
    var connection_ref = beam.ResourceRef(Connection).init(connection);
    errdefer connection_ref.deinit();
    const resource = ResultKind.resource.make(environment, .{
        .value = query_result,
        .connection = connection_ref,
    }) catch return Error.FailedToCreateResource;
    connection_ref.resource = null;
    return resource;
}

fn closeResult(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchResult(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn prepare(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const connection = try fetchConnection(environment, args[0]);
    const sql = try beam.get_char_slice(environment, args[1]);
    const terminated = try beam.allocator.dupeZ(u8, sql);
    defer beam.allocator.free(terminated);
    if (connection.close_requested.load(.acquire)) return Error.ClosedConnection;
    lock(&connection.mutex);
    defer connection.mutex.unlock();
    if (connection.handle == null) return Error.ClosedConnection;
    var handle: duckdb.duckdb_prepared_statement = null;
    if (duckdb.duckdb_prepare(connection.handle, terminated.ptr, &handle) != duckdb.DuckDBSuccess)
        return Error.FailedToPrepare;
    errdefer duckdb.duckdb_destroy_prepare(&handle);
    _ = connection.children.fetchAdd(1, .acq_rel);
    errdefer connection.releaseChild();
    var connection_ref = beam.ResourceRef(Connection).init(connection);
    errdefer connection_ref.deinit();
    const resource = PreparedKind.resource.make(environment, .{
        .handle = handle,
        .connection = connection_ref,
    }) catch return Error.FailedToCreateResource;
    connection_ref.resource = null;
    return resource;
}

fn closePrepared(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchPrepared(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn bindPreparedValues(environment: beam.env, prepared: *Prepared, source: beam.term) !void {
    var values = source;
    if (prepared.handle == null or prepared.close_requested.load(.acquire)) return Error.ClosedPrepared;
    const count = try beam.get_list_length(environment, values);
    if (count != duckdb.duckdb_nparams(prepared.handle)) return Error.FailedToBind;
    if (duckdb.duckdb_clear_bindings(prepared.handle) != duckdb.DuckDBSuccess) return Error.FailedToBind;

    var index: usize = 1;
    while (try beam.get_list_length(environment, values) > 0) : (index += 1) {
        const tagged = try getTuple(environment, try beam.get_head_and_iter(environment, &values));
        if (tagged.len == 0) return Error.FailedToBind;
        const tag = try beam.get_atom_slice(environment, tagged[0]);
        defer beam.allocator.free(tag);

        const status = if (std.mem.eql(u8, tag, "null"))
            duckdb.duckdb_bind_null(prepared.handle, index)
        else if (tagged.len == 2 and std.mem.eql(u8, tag, "boolean"))
            duckdb.duckdb_bind_boolean(prepared.handle, index, try beam.get_bool(environment, tagged[1]))
        else if (tagged.len == 2 and std.mem.eql(u8, tag, "integer"))
            duckdb.duckdb_bind_int64(prepared.handle, index, try beam.get_i64(environment, tagged[1]))
        else if (tagged.len == 2 and std.mem.eql(u8, tag, "float"))
            duckdb.duckdb_bind_double(prepared.handle, index, try beam.get_f64(environment, tagged[1]))
        else if (tagged.len == 2 and std.mem.eql(u8, tag, "string")) blk: {
            const string = try beam.get_char_slice(environment, tagged[1]);
            break :blk duckdb.duckdb_bind_varchar_length(prepared.handle, index, string.ptr, string.len);
        } else return Error.FailedToBind;

        if (status != duckdb.DuckDBSuccess) return Error.FailedToBind;
    }
}

fn bindPrepared(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const prepared = try fetchPrepared(environment, args[0]);
    lock(&prepared.mutex);
    defer prepared.mutex.unlock();
    try bindPreparedValues(environment, prepared, args[1]);
    return beam.make_ok(environment);
}

fn createPending(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const prepared = try fetchPrepared(environment, args[0]);
    lock(&prepared.mutex);
    defer prepared.mutex.unlock();
    if (prepared.handle == null or prepared.close_requested.load(.acquire)) return Error.ClosedPrepared;
    try bindPreparedValues(environment, prepared, args[1]);
    var handle: duckdb.duckdb_pending_result = null;
    if (duckdb.duckdb_pending_prepared(prepared.handle, &handle) != duckdb.DuckDBSuccess)
        return Error.FailedToCreatePending;
    errdefer duckdb.duckdb_destroy_pending(&handle);
    _ = prepared.children.fetchAdd(1, .acq_rel);
    errdefer prepared.releaseChild();
    var prepared_ref = beam.ResourceRef(Prepared).init(prepared);
    errdefer prepared_ref.deinit();
    const resource = PendingKind.resource.make(environment, .{
        .handle = handle,
        .prepared = prepared_ref,
    }) catch return Error.FailedToCreateResource;
    prepared_ref.resource = null;
    return resource;
}

fn closePending(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchPending(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn pendingTask(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const pending = try fetchPending(environment, args[0]);
    lock(&pending.mutex);
    defer pending.mutex.unlock();
    if (pending.handle == null) return Error.ClosedPending;
    return switch (duckdb.duckdb_pending_execute_task(pending.handle)) {
        duckdb.DUCKDB_PENDING_RESULT_READY => beam.make_atom(environment, "ready"),
        duckdb.DUCKDB_PENDING_RESULT_NOT_READY => beam.make_atom(environment, "not_ready"),
        duckdb.DUCKDB_PENDING_NO_TASKS_AVAILABLE => beam.make_atom(environment, "no_tasks"),
        else => beam.make_atom(environment, "error"),
    };
}

fn pendingError(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const pending = try fetchPending(environment, args[0]);
    lock(&pending.mutex);
    defer pending.mutex.unlock();
    if (pending.handle == null) return Error.ClosedPending;
    const message = duckdb.duckdb_pending_error(pending.handle);
    if (message == null) return beam.make_slice(environment, "DuckDB pending query failed");
    return beam.make_slice(environment, std.mem.span(message));
}

fn executePending(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const pending = try fetchPending(environment, args[0]);
    lock(&pending.mutex);
    defer pending.mutex.unlock();
    if (pending.handle == null) return Error.ClosedPending;
    var query_result: duckdb.duckdb_result = std.mem.zeroes(duckdb.duckdb_result);
    if (duckdb.duckdb_execute_pending(pending.handle, &query_result) != duckdb.DuckDBSuccess) {
        duckdb.duckdb_destroy_result(&query_result);
        return Error.PendingNotReady;
    }
    errdefer duckdb.duckdb_destroy_result(&query_result);
    const connection = pending.prepared.get().connection.get();
    _ = connection.children.fetchAdd(1, .acq_rel);
    errdefer connection.releaseChild();
    var connection_ref = beam.ResourceRef(Connection).init(connection);
    errdefer connection_ref.deinit();
    const resource = ResultKind.resource.make(environment, .{
        .value = query_result,
        .connection = connection_ref,
    }) catch return Error.FailedToCreateResource;
    connection_ref.resource = null;
    return resource;
}

fn interrupt(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const connection = try fetchConnection(environment, args[0]);
    if (connection.handle != null) duckdb.duckdb_interrupt(connection.handle);
    return beam.make_ok(environment);
}

fn resultColumnCount(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const value = try fetchResult(environment, args[0]);
    lock(&value.mutex);
    defer value.mutex.unlock();
    if (!value.alive) return Error.ClosedResult;
    return beam.make_usize(environment, duckdb.duckdb_column_count(&value.value));
}

fn resultRowCount(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const value = try fetchResult(environment, args[0]);
    lock(&value.mutex);
    defer value.mutex.unlock();
    if (!value.alive) return Error.ClosedResult;
    return beam.make_usize(environment, duckdb.duckdb_row_count(&value.value));
}

fn resultRowsChanged(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const value = try fetchResult(environment, args[0]);
    lock(&value.mutex);
    defer value.mutex.unlock();
    if (!value.alive) return Error.ClosedResult;
    return beam.make_usize(environment, duckdb.duckdb_rows_changed(&value.value));
}

fn resultColumnName(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const value = try fetchResult(environment, args[0]);
    const column = try beam.get_usize(environment, args[1]);
    lock(&value.mutex);
    defer value.mutex.unlock();
    if (!value.alive) return Error.ClosedResult;
    if (column >= duckdb.duckdb_column_count(&value.value)) return Error.InvalidIndex;
    return beam.make_slice(environment, std.mem.span(duckdb.duckdb_column_name(&value.value, column)));
}

fn resultValue(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const value = try fetchResult(environment, args[0]);
    const column = try beam.get_usize(environment, args[1]);
    const row = try beam.get_usize(environment, args[2]);
    lock(&value.mutex);
    defer value.mutex.unlock();
    if (!value.alive) return Error.ClosedResult;
    if (column >= duckdb.duckdb_column_count(&value.value) or
        row >= duckdb.duckdb_row_count(&value.value)) return Error.InvalidIndex;
    if (duckdb.duckdb_value_is_null(&value.value, column, row)) return beam.make_nil(environment);

    return switch (duckdb.duckdb_column_type(&value.value, column)) {
        duckdb.DUCKDB_TYPE_BOOLEAN => beam.make_bool(environment, duckdb.duckdb_value_boolean(&value.value, column, row)),
        duckdb.DUCKDB_TYPE_TINYINT,
        duckdb.DUCKDB_TYPE_SMALLINT,
        duckdb.DUCKDB_TYPE_INTEGER,
        duckdb.DUCKDB_TYPE_BIGINT,
        => beam.make_i64(environment, duckdb.duckdb_value_int64(&value.value, column, row)),
        duckdb.DUCKDB_TYPE_FLOAT, duckdb.DUCKDB_TYPE_DOUBLE => beam.make_f64(environment, duckdb.duckdb_value_double(&value.value, column, row)),
        else => blk: {
            const string = duckdb.duckdb_value_varchar(&value.value, column, row);
            defer duckdb.duckdb_free(string);
            break :blk beam.make_slice(environment, std.mem.span(string));
        },
    };
}

fn createAppender(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const connection = try fetchConnection(environment, args[0]);
    if (connection.close_requested.load(.acquire)) return Error.ClosedConnection;
    const table = try beam.get_char_slice(environment, args[1]);
    const terminated = try beam.allocator.dupeZ(u8, table);
    defer beam.allocator.free(terminated);
    lock(&connection.mutex);
    defer connection.mutex.unlock();
    if (connection.handle == null) return Error.ClosedConnection;
    var handle: duckdb.duckdb_appender = null;
    if (duckdb.duckdb_appender_create(connection.handle, null, terminated.ptr, &handle) != duckdb.DuckDBSuccess)
        return Error.FailedToCreateAppender;
    errdefer _ = duckdb.duckdb_appender_destroy(&handle);
    _ = connection.children.fetchAdd(1, .acq_rel);
    errdefer connection.releaseChild();
    var connection_ref = beam.ResourceRef(Connection).init(connection);
    errdefer connection_ref.deinit();
    const resource = AppenderKind.resource.make(environment, .{
        .handle = handle,
        .connection = connection_ref,
    }) catch return Error.FailedToCreateResource;
    connection_ref.resource = null;
    return resource;
}

fn closeAppender(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    (try fetchAppender(environment, args[0])).close();
    return beam.make_ok(environment);
}

fn appendRow(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const appender = try fetchAppender(environment, args[0]);
    var values = args[1];
    lock(&appender.mutex);
    defer appender.mutex.unlock();
    if (appender.handle == null) return Error.ClosedAppender;
    if (duckdb.duckdb_appender_begin_row(appender.handle) != duckdb.DuckDBSuccess) return Error.FailedToAppend;

    while (try beam.get_list_length(environment, values) > 0) {
        const tagged = try getTuple(environment, try beam.get_head_and_iter(environment, &values));
        if (tagged.len == 0) return Error.FailedToAppend;
        const tag = try beam.get_atom_slice(environment, tagged[0]);
        defer beam.allocator.free(tag);

        const status = if (std.mem.eql(u8, tag, "null"))
            duckdb.duckdb_append_null(appender.handle)
        else if (tagged.len == 2 and std.mem.eql(u8, tag, "boolean"))
            duckdb.duckdb_append_bool(appender.handle, try beam.get_bool(environment, tagged[1]))
        else if (tagged.len == 2 and std.mem.eql(u8, tag, "integer"))
            duckdb.duckdb_append_int64(appender.handle, try beam.get_i64(environment, tagged[1]))
        else if (tagged.len == 2 and std.mem.eql(u8, tag, "float"))
            duckdb.duckdb_append_double(appender.handle, try beam.get_f64(environment, tagged[1]))
        else if (tagged.len == 2 and std.mem.eql(u8, tag, "string")) blk: {
            const string = try beam.get_char_slice(environment, tagged[1]);
            break :blk duckdb.duckdb_append_varchar_length(appender.handle, string.ptr, string.len);
        } else return Error.FailedToAppend;

        if (status != duckdb.DuckDBSuccess) return Error.FailedToAppend;
    }

    if (duckdb.duckdb_appender_end_row(appender.handle) != duckdb.DuckDBSuccess) return Error.FailedToAppend;
    return beam.make_ok(environment);
}

fn appendBegin(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const appender = try fetchAppender(environment, args[0]);
    lock(&appender.mutex);
    defer appender.mutex.unlock();
    if (appender.handle == null) return Error.ClosedAppender;
    if (duckdb.duckdb_appender_begin_row(appender.handle) != duckdb.DuckDBSuccess) return Error.FailedToAppend;
    return beam.make_ok(environment);
}

fn appendEnd(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const appender = try fetchAppender(environment, args[0]);
    lock(&appender.mutex);
    defer appender.mutex.unlock();
    if (appender.handle == null) return Error.ClosedAppender;
    if (duckdb.duckdb_appender_end_row(appender.handle) != duckdb.DuckDBSuccess) return Error.FailedToAppend;
    return beam.make_ok(environment);
}

fn appendNull(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const appender = try fetchAppender(environment, args[0]);
    lock(&appender.mutex);
    defer appender.mutex.unlock();
    if (appender.handle == null or duckdb.duckdb_append_null(appender.handle) != duckdb.DuckDBSuccess)
        return Error.FailedToAppend;
    return beam.make_ok(environment);
}

fn appendBool(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const appender = try fetchAppender(environment, args[0]);
    const value = try beam.get_bool(environment, args[1]);
    lock(&appender.mutex);
    defer appender.mutex.unlock();
    if (appender.handle == null or duckdb.duckdb_append_bool(appender.handle, value) != duckdb.DuckDBSuccess)
        return Error.FailedToAppend;
    return beam.make_ok(environment);
}

fn appendInt64(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const appender = try fetchAppender(environment, args[0]);
    const value = try beam.get_i64(environment, args[1]);
    lock(&appender.mutex);
    defer appender.mutex.unlock();
    if (appender.handle == null or duckdb.duckdb_append_int64(appender.handle, value) != duckdb.DuckDBSuccess)
        return Error.FailedToAppend;
    return beam.make_ok(environment);
}

fn appendDouble(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const appender = try fetchAppender(environment, args[0]);
    const value = try beam.get_f64(environment, args[1]);
    lock(&appender.mutex);
    defer appender.mutex.unlock();
    if (appender.handle == null or duckdb.duckdb_append_double(appender.handle, value) != duckdb.DuckDBSuccess)
        return Error.FailedToAppend;
    return beam.make_ok(environment);
}

fn appendVarchar(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const appender = try fetchAppender(environment, args[0]);
    const value = try beam.get_char_slice(environment, args[1]);
    lock(&appender.mutex);
    defer appender.mutex.unlock();
    if (appender.handle == null or
        duckdb.duckdb_append_varchar_length(appender.handle, value.ptr, value.len) != duckdb.DuckDBSuccess)
        return Error.FailedToAppend;
    return beam.make_ok(environment);
}

fn flushAppender(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const appender = try fetchAppender(environment, args[0]);
    lock(&appender.mutex);
    defer appender.mutex.unlock();
    if (appender.handle == null or duckdb.duckdb_appender_flush(appender.handle) != duckdb.DuckDBSuccess)
        return Error.FailedToFlushAppender;
    return beam.make_ok(environment);
}

fn queryInt64(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const path = try beam.get_char_slice(environment, args[0]);
    const sql = try beam.get_char_slice(environment, args[1]);
    const terminated_path = try beam.allocator.dupeZ(u8, path);
    defer beam.allocator.free(terminated_path);
    const terminated_sql = try beam.allocator.dupeZ(u8, sql);
    defer beam.allocator.free(terminated_sql);
    var database: duckdb.duckdb_database = null;
    if (duckdb.duckdb_open(terminated_path.ptr, &database) != duckdb.DuckDBSuccess) return Error.FailedToOpenDatabase;
    defer duckdb.duckdb_close(&database);
    var connection: duckdb.duckdb_connection = null;
    if (duckdb.duckdb_connect(database, &connection) != duckdb.DuckDBSuccess) return Error.FailedToConnect;
    defer duckdb.duckdb_disconnect(&connection);
    var query_result: duckdb.duckdb_result = std.mem.zeroes(duckdb.duckdb_result);
    if (duckdb.duckdb_query(connection, terminated_sql.ptr, &query_result) != duckdb.DuckDBSuccess) {
        duckdb.duckdb_destroy_result(&query_result);
        return Error.FailedToQuery;
    }
    defer duckdb.duckdb_destroy_result(&query_result);
    return beam.make_i64(environment, duckdb.duckdb_value_int64(&query_result, 0, 0));
}

const all_nifs = .{
    result.nif("library_version", 0, libraryVersion).entry,
    result.nif_with_flags("query_int64", 2, queryInt64, io_bound).entry,
    result.nif_with_flags("open", 1, open, io_bound).entry,
    result.nif("close_database", 1, closeDatabase).entry,
    result.nif("connect", 1, connect).entry,
    result.nif("close_connection", 1, closeConnection).entry,
    result.nif_with_flags("query", 2, query, io_bound).entry,
    result.nif("close_result", 1, closeResult).entry,
    result.nif("prepare", 2, prepare).entry,
    result.nif("close_prepared", 1, closePrepared).entry,
    result.nif("bind_prepared", 2, bindPrepared).entry,
    result.nif("create_pending", 2, createPending).entry,
    result.nif("close_pending", 1, closePending).entry,
    result.nif_with_flags("pending_task", 1, pendingTask, 1).entry,
    result.nif("pending_error", 1, pendingError).entry,
    result.nif("execute_pending", 1, executePending).entry,
    result.nif("interrupt", 1, interrupt).entry,
    result.nif("result_column_count", 1, resultColumnCount).entry,
    result.nif("result_row_count", 1, resultRowCount).entry,
    result.nif("result_rows_changed", 1, resultRowsChanged).entry,
    result.nif("result_column_name", 2, resultColumnName).entry,
    result.nif("result_value", 3, resultValue).entry,
    result.nif("create_appender", 2, createAppender).entry,
    result.nif("close_appender", 1, closeAppender).entry,
    result.nif("append_row", 2, appendRow).entry,
    result.nif("append_begin", 1, appendBegin).entry,
    result.nif("append_end", 1, appendEnd).entry,
    result.nif("append_null", 1, appendNull).entry,
    result.nif("append_bool", 2, appendBool).entry,
    result.nif("append_int64", 2, appendInt64).entry,
    result.nif("append_double", 2, appendDouble).entry,
    result.nif("append_varchar", 2, appendVarchar).entry,
    result.nif("flush_appender", 1, flushAppender).entry,
};

const Resources = kinda.ResourceRegistry(.{
    kinda.ResourceRegistration{ .kind = DatabaseKind },
    kinda.ResourceRegistration{ .kind = ConnectionKind },
    kinda.ResourceRegistration{ .kind = ResultKind },
    kinda.ResourceRegistration{ .kind = AppenderKind },
    kinda.ResourceRegistration{ .kind = PreparedKind },
    kinda.ResourceRegistration{ .kind = PendingKind },
});

const nif_exports = kinda.EntryExports(.{
    .name = root_module,
    .nifs = all_nifs,
    .load = nif_load,
    .upgrade = nif_upgrade,
});

comptime {
    _ = nif_exports;
}

export fn nif_load(environment: beam.env, _: [*c]?*anyopaque, _: beam.term) c_int {
    return Resources.open(environment);
}

export fn nif_upgrade(environment: beam.env, private_data: [*c]?*anyopaque, _: [*c]?*anyopaque, load_info: beam.term) c_int {
    return nif_load(environment, private_data, load_info);
}
