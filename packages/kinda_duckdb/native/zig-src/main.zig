const std = @import("std");
const builtin = @import("builtin");
const kinda = @import("kinda");
const beam = kinda.beam;
const e = kinda.erl_nif;
const result = kinda.result;
const duckdb = @cImport({
    @cInclude("duckdb.h");
});

const root_module = "Elixir.Kinda.DuckDB.Native";
const io_bound: u32 = 2;

const Error = error{
    FailedToOpenDatabase,
    FailedToConnect,
    FailedToQuery,
    EmptyResult,
};

fn libraryVersion(environment: beam.env, _: c_int, _: [*c]const beam.term) !beam.term {
    return beam.make_slice(environment, std.mem.span(duckdb.duckdb_library_version()));
}

fn queryInt64(environment: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
    const path = try beam.get_char_slice(environment, args[0]);
    const sql = try beam.get_char_slice(environment, args[1]);
    const terminated_path = try beam.allocator.dupeZ(u8, path);
    defer beam.allocator.free(terminated_path);
    const terminated_sql = try beam.allocator.dupeZ(u8, sql);
    defer beam.allocator.free(terminated_sql);

    var database: duckdb.duckdb_database = null;
    if (duckdb.duckdb_open(terminated_path.ptr, &database) != duckdb.DuckDBSuccess)
        return Error.FailedToOpenDatabase;
    defer duckdb.duckdb_close(&database);

    var connection: duckdb.duckdb_connection = null;
    if (duckdb.duckdb_connect(database, &connection) != duckdb.DuckDBSuccess)
        return Error.FailedToConnect;
    defer duckdb.duckdb_disconnect(&connection);

    var query_result: duckdb.duckdb_result = undefined;
    if (duckdb.duckdb_query(connection, terminated_sql.ptr, &query_result) != duckdb.DuckDBSuccess)
        return Error.FailedToQuery;
    defer duckdb.duckdb_destroy_result(&query_result);

    if (duckdb.duckdb_row_count(&query_result) == 0 or
        duckdb.duckdb_column_count(&query_result) == 0)
        return Error.EmptyResult;

    return beam.make_i64(environment, duckdb.duckdb_value_int64(&query_result, 0, 0));
}

const all_nifs = .{
    result.nif("library_version", 0, libraryVersion).entry,
    result.nif_with_flags("query_int64", 2, queryInt64, io_bound).entry,
};
pub export var nifs: [all_nifs.len]e.ErlNifFunc = all_nifs;

const entry = e.ErlNifEntry{
    .major = 2,
    .minor = 16,
    .name = root_module,
    .num_of_funcs = nifs.len,
    .funcs = &(nifs[0]),
    .load = null,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = "beam.vanilla",
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit),
    .min_erts = "erts-15.0",
};

const NifInit = if (builtin.os.tag == .windows) struct {
    var callbacks: e.TWinDynNifCallbacks = undefined;

    fn init(win_callbacks: *const e.TWinDynNifCallbacks) callconv(.c) *const e.ErlNifEntry {
        callbacks = win_callbacks.*;
        return &entry;
    }

    fn exportSymbols() void {
        @export(&callbacks, .{ .name = "WinDynNifCallbacks" });
        @export(&init, .{ .name = "nif_init" });
    }
} else struct {
    fn init() callconv(.c) *const e.ErlNifEntry {
        return &entry;
    }

    fn exportSymbols() void {
        @export(&init, .{ .name = "nif_init" });
    }
};

comptime {
    NifInit.exportSymbols();
}
