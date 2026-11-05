//! This struct contains adapters designed to facilitate interfacing the
//! BEAM's c-style helpers for NIFs with a more idiomatic Zig-style of
//! programming, for example, the use of slices instead of null-terminated
//! arrays as strings.
//!
//! This struct derives from `zig/beam/beam.zig`, and you may import it into
//! your module's zig code by calling:
//!
//! ```
//! const beam = @import("beam.zig")
//! ```
//!
//! This is done automatically for you inside your `~Z` forms, so do NOT
//! use this import statement with inline Zig.
//!
//! ## Features
//!
//! ### The BEAM Allocator
//!
//! Wraps `e.enif_alloc` and `e.enif_free` functions into a compliant Zig
//! allocator struct.  You should thus be able to supply Zig standard library
//! functions which require an allocator a struct that is compliant with its
//! requirements.
//!
//! This is, in particular, useful for slice generation.
//!
//! #### Example (slice generation)
//!
//! ```
//! beam = @import("beam.zig");
//!
//! fn make_a_slice_of_floats() ![]f32 {
//!   return beam.allocator.alloc(f32, 100);
//! }
//! ```
//!
//! Because Zig features *composable allocators*, you can very easily implement
//! custom allocators on top of the existing BEAM allocator.
//!
//! ### Getters
//!
//! Erlang's NIF interface provides a comprehensive set of methods to retrieve
//! data out of BEAM terms.  However, this set of methods presents an error
//! handling scheme that is designed for C and inconsistent with the idiomatic
//! scheme used for Zig best practices.
//!
//! A series of get functions is provided, implementing these methods in
//! accordance to best practices.  These include `get/3`, which is the generic
//! method for getting scalar values, `get_X`, which are typed methods for
//! retrieving scalar values, and `get_slice_of/3`, which is the generic method
//! for retrieving a Zig slice from a BEAM list.
//!
//! Naturally, for all of these functions, you will have to provide the BEAM
//! environment value.
//!
//! #### Examples
//!
//! ```
//! const beam = @import("beam.zig");
//!
//! fn double_value(env: beam.env, value: beam.term) !f64 {
//!   return (try beam.get_f64(env, value)) * 2;
//! }
//!
//! fn sum_float_list(env: beam.env, list: beam.term) !f64 {
//!   zig_list: []f64 = try beam.get_slice_of(f64, env, list);
//!   defer beam.allocator.free(zig_list);  // don't forget to clean up!
//!
//!   result: f64 = 0;
//!   for (list) |item| { result += item; }
//!   return result;
//! }
//! ```
//!
//! ### Makers
//!
//! A series of "make" functions is provided which allow for easy export of
//! Zig values back to the BEAM.  Typically, these functions are used in the
//! automatic type marshalling performed by Zigler, however, you may want to
//! be able to use them yourself to assemble BEAM datatypes not directly
//! supported by Zig.  For example, a custom tuple value.
//!
//! #### Example
//!
//! ```
//! const beam = @import("beam.zig");
//!
//! const ok_slice="ok"[0..];
//! fn to_ok_tuple(env: beam.env, value: i64) !beam.term {
//!   var tuple_slice: []term = try beam.allocator.alloc(beam.term, 2);
//!   defer beam.allocator.free(tuple_slice);
//!
//!   tuple_slice[0] = beam.make_atom(env, ok_slice);
//!   tuple_slice[1] = beam.make_i64(env, value);
//!
//!   return beam.make_tuple(env, tuple_slice);
//! }
//!
//! ```

const e = @import("kinda.zig").erl_nif;
const nifApi = @import("kinda.zig").nifApi;
const std = @import("std");
const builtin = @import("builtin");

///////////////////////////////////////////////////////////////////////////////
// BEAM allocator definitions
///////////////////////////////////////////////////////////////////////////////

const Allocator = std.mem.Allocator;

// basic allocator

/// !value
/// provides a default BEAM allocator.  This is an implementation of the Zig
/// allocator interface.  Use `beam.allocator.alloc` everywhere to safely
/// allocate slices efficiently, and use `beam.allocator.free` to release that
/// memory.  For single item allocation, use `beam.allocator.create` and
/// `beam.allocator.destroy` to release the memory.
///
/// Note this does not make the allocated memory *garbage collected* by the
/// BEAM.
///
/// All memory will be tracked by the beam.  All allocations happen with 8-byte
/// alignment, as described in `erl_nif.h`.  This is sufficient to create
/// correctly aligned `beam.terms`, and for most purposes.
/// For data that require greater alignment, use `beam.large_allocator`.
///
/// ### Example
///
/// The following code will return ten bytes of new memory.
///
/// ```zig
/// const beam = @import("beam.zig");
///
/// fn give_me_ten_bytes() ![]u8 {
///   return beam.allocator.alloc(u8, 10);
/// }
/// ```
///
/// Allocations are backed by ERTS; shrinking retains the existing allocation.
/// Alignments greater than eight bytes require a separate allocator.
pub const allocator = raw_beam_allocator;

pub const MAX_ALIGN: mem.Alignment = .@"8";

const raw_beam_allocator = Allocator{ .ptr = undefined, .vtable = &raw_beam_allocator_vtable };
const raw_beam_allocator_vtable = Allocator.VTable{ .alloc = raw_beam_alloc, .resize = raw_beam_resize, .free = raw_beam_free, .remap = remap };

fn raw_beam_alloc(_: *anyopaque, len: usize, ptr_align: mem.Alignment, _: usize) ?[*]u8 {
    if (ptr_align.compare(.gt, MAX_ALIGN)) return null;
    const ptr = nifApi("enif_alloc")(len) orelse return null;
    return @as([*]u8, @ptrCast(ptr));
}

fn raw_beam_resize(_: *anyopaque, buf: []u8, _: mem.Alignment, new_len: usize, _: usize) bool {
    if (new_len == 0) {
        nifApi("enif_free")(buf.ptr);
        return true;
    }
    if (new_len <= buf.len) return true;
    return false;
}

fn raw_beam_free(_: *anyopaque, buf: []u8, _: mem.Alignment, _: usize) void {
    nifApi("enif_free")(buf.ptr);
}

fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    // can't use realloc directly because it might not respect alignment.
    return if (raw_beam_resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
}

///////////////////////////////////////////////////////////////////////////////
// syntactic sugar: important elixir terms
///////////////////////////////////////////////////////////////////////////////

/// errors for nif translation
pub const Error =
    error{ @"Function clause error", @"Fail to make resource", @"Fail to fetch resource", @"Fail to fetch resource ptr", @"Fail to fetch resource for array", @"Fail to fetch resource list element", @"Fail to make resource for opaque array", @"Fail to fetch primitive", @"Fail to create primitive", @"Fail to make resource for return type", @"Fail to allocate memory for tuple slice", @"Fail to make ptr resource", @"Fail to fetch ptr resource", @"Fail to make resource for opaque ptr", @"Fail to make array resource", @"Fail to make mutable array resource", @"Fail to fetch resource opaque ptr", @"Fail to fetch offset", @"Fail to make resource for extracted object", @"Fail to make object size", @"Fail to inspect resource binary", @"Fail to get boolean", @"Fail to get calling process" };

/// errors for launching nif errors
/// LaunchError Occurs when there's a problem launching a threaded nif.
/// syntactic sugar for the BEAM environment.  Note that the `env` type
/// encapsulates the pointer, since you will almost always be passing this
/// pointer to an opaque struct around without accessing it.
pub const env = ?*e.ErlNifEnv;

/// syntactic sugar for the BEAM term struct (`e.ERL_NIF_TERM`)
pub const term = e.ERL_NIF_TERM;

///////////////////////////////////////////////////////////////////////////////
// syntactic sugar: gets
///////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////
// generics

/// A helper for marshalling values from the BEAM runtime into Zig.  Use this
/// function if you need support for Zig generics.
///
/// Used internally to typeheck values coming into Zig slice.
///
/// supported types:
/// - `c_int`
/// - `c_long`
/// - `isize`
/// - `usize`
/// - `u8`
/// - `i32`
/// - `i64`
/// - `f16`
/// - `f32`
/// - `f64`
pub fn get(comptime T: type, env_: env, value: term) !T {
    inline for (.{ c_int, c_uint, c_long, isize, usize, u8, u16, u32, u64, i8, i16, i32, i64, f16, f32, f64, bool }) |Value| {
        if (T == Value) return @field(@This(), "get_" ++ @typeName(Value))(env_, value);
    }
    return Error.@"Function clause error";
}

///////////////////////////////////////////////////////////////////////////////
// ints

/// Takes a BEAM int term and returns a `c_int` value.  Should only be used for
/// C interop with Zig functions.
///
// Keep the public typed entry points while sharing conversion and range checks.
fn Number(comptime T: type, comptime Native: type, comptime getter: []const u8, comptime maker: []const u8) type {
    return struct {
        fn get(environment: env, value: term) !T {
            var decoded: Native = undefined;
            if (nifApi("enif_get_" ++ getter)(environment, value, &decoded) == 0)
                return Error.@"Function clause error";
            if (@typeInfo(T) == .float) return @floatCast(decoded);
            if (T == u8 or T == u16 or T == i8 or T == i16)
                return std.math.cast(T, decoded) orelse Error.@"Function clause error";
            return @intCast(decoded);
        }

        fn make(environment: env, value: T) term {
            return nifApi("enif_make_" ++ maker)(environment, if (@typeInfo(T) == .float) @floatCast(value) else @intCast(value));
        }
    };
}

pub const get_c_int = Number(c_int, c_int, "int", "int").get;

/// Takes a BEAM int term and returns a `c_uint` value.  Should only be used for
/// C interop with Zig functions.
///
pub const get_c_uint = Number(c_uint, c_uint, "uint", "uint").get;

/// Takes a BEAM int term and returns a `c_long` value.  Should only be used
/// for C interop with Zig functions.
///
pub const get_c_long = Number(c_long, c_long, "long", "long").get;

/// Takes a BEAM int term and returns a `c_ulong` value.  Should only be used
/// for C interop with Zig functions.
///
pub const get_c_ulong = Number(c_ulong, c_ulong, "ulong", "ulong").get;

/// Takes a BEAM int term and returns a `isize` value.  Should only be used
/// for C interop.
///
pub const get_isize = Number(isize, i64, "int64", "int64").get;

/// Takes a BEAM int term and returns a `usize` value.  Zig idiomatically uses
/// `usize` for its size values, so typically you should be using this function.
///
pub const get_usize = Number(usize, u64, "uint64", "uint64").get;

/// Takes a BEAM int term and returns a `u8` value.
///
/// Note that this conversion function checks to make sure it's in range
/// (`0..255`).
///
pub const get_u8 = Number(u8, c_int, "int", "uint").get;

/// Takes a BEAM int term and returns a `u16` value.
///
/// Note that this conversion function checks to make sure it's in range
/// (`0..65535`).
///
pub const get_u16 = Number(u16, c_int, "int", "uint").get;

/// Takes a BEAM int term and returns a `u32` value.
///
pub const get_u32 = Number(u32, c_uint, "uint", "uint").get;

/// Takes a BEAM int term and returns a `u64` value.
///
pub const get_u64 = Number(u64, u64, "uint64", "uint64").get;

/// Takes a BEAM int term and returns an `i8` value.
///
/// Note that this conversion function checks to make sure it's in range
/// (`-128..127`).
///
pub const get_i8 = Number(i8, c_int, "int", "int").get;

/// Takes a BEAM int term and returns an `i16` value.
///
/// Note that this conversion function checks to make sure it's in range
/// (`-32768..32767`).
///
pub const get_i16 = Number(i16, c_int, "int", "int").get;

/// Takes a BEAM int term and returns an `i32` value.
///
/// Note that this conversion function does not currently do range checking.
///
pub const get_i32 = Number(i32, c_int, "int", "int").get;

/// Takes a BEAM int term and returns an `i64` value.
///
/// Note that this conversion function does not currently do range checking.
///
pub const get_i64 = Number(i64, i64, "int64", "int64").get;

///////////////////////////////////////////////////////////////////////////////
// floats

/// Takes a BEAM float term and returns an `f16` value.
///
/// Note that this conversion function does not currently do range checking.
///
pub const get_f16 = Number(f16, f64, "double", "double").get;

/// Takes a BEAM float term and returns an `f32` value.
///
/// Note that this conversion function does not currently do range checking.
///
pub const get_f32 = Number(f32, f64, "double", "double").get;

/// Takes a BEAM float term and returns an `f64` value.
///
pub const get_f64 = Number(f64, f64, "double", "double").get;

///////////////////////////////////////////////////////////////////////////////
// atoms

/// note that Zig has no equivalent of a BEAM atom, so we will just declare
/// it as a term.  You can retrieve the string value of the BEAM atom using
/// `get_atom_slice/2`
pub const atom = term;

const __latin1 = e.ERL_NIF_LATIN1;

/// Takes a BEAM atom term and retrieves it as a slice `[]u8` value.
/// it's the caller's responsibility to make sure that the value is freed.
///
/// Uses the standard `beam.allocator` allocator.  If you require a custom
/// allocator, use `get_atom_slice_alloc/3`
///
pub fn get_atom_slice(environment: env, src_term: atom) ![]u8 {
    return get_atom_slice_alloc(allocator, environment, src_term);
}

/// Takes a BEAM atom term and retrieves it as a slice `[]u8` value, with
/// any allocator.
///
pub fn get_atom_slice_alloc(a: Allocator, environment: env, src_term: atom) ![]u8 {
    var len: c_uint = undefined;
    var result: []u8 = undefined;
    if (0 != nifApi("enif_get_atom_length")(environment, src_term, @ptrCast(&len), __latin1)) {
        result = try a.alloc(u8, len + 1);

        // pull the value from the beam.
        if (0 != nifApi("enif_get_atom")(environment, src_term, @ptrCast(&result[0]), len + 1, __latin1)) {
            // trim the slice, it's the caller's responsibility to free it.
            return result[0..len];
        } else {
            unreachable;
        }
    } else {
        return Error.@"Function clause error";
    }
}

///////////////////////////////////////////////////////////////////////////////
// binaries

/// shorthand for `e.ErlNifBinary`.
pub const binary = e.ErlNifBinary;

/// Takes an BEAM `t:binary/0` term and retrieves it as a Zig character slice
/// (`[]u8`)  No memory is allocated for this operation.
///
pub fn get_char_slice(environment: env, src_term: term) ![]u8 {
    const bin = try get_binary(environment, src_term);
    return bin.data[0..bin.size];
}

/// Takes an BEAM `t:binary/0` term and returns the corresponding
/// `binary` struct.
///
pub fn get_binary(environment: env, src_term: term) !binary {
    var bin: binary = undefined;
    return if (0 != nifApi("enif_inspect_binary")(environment, src_term, &bin)) bin else Error.@"Function clause error";
}

///////////////////////////////////////////////////////////////////////////////
// pids

/// shorthand for `e.ErlNifPid`.
pub const pid = e.ErlNifPid;

/// shortcut for `e.enif_self`, marshalling into zig error style.
///
/// returns the pid value if it's env is a process-bound environment, otherwise
/// running the wrapped function.  That way, `beam.self()` is safe to use when
/// you swap between different execution modes.
///
/// if you need the process mailbox for the actual spawned thread, use `e.enif_self`
pub fn self(environment: env) !pid {
    var p: pid = undefined;
    return (nifApi("enif_self")(environment, &p) orelse return Error.@"Fail to get calling process").*;
}

/// shortcut for `e.enif_send`
///
/// returns true if the send is successful, false otherwise.
///
/// if you are sending from a thread that does not have a BEAM environment, you
/// should put `null` in both environment variables.
pub fn send_advanced(c_env: env, to_pid: pid, m_env: env, msg: term) bool {
    return (nifApi("enif_send")(c_env, &to_pid, m_env, msg) == 1);
}

///////////////////////////////////////////////////////////////////////////////
// tuples

///////////////////////////////////////////////////////////////////////////////
// lists

/// Takes a BEAM `t:list/0` term and returns its length.
///
pub fn get_list_length(environment: env, list: term) !usize {
    var result: c_uint = undefined;
    return if (0 != nifApi("enif_get_list_length")(environment, list, &result)) @intCast(result) else Error.@"Function clause error";
}

/// Iterates over a BEAM `t:list/0`.
///
/// In this function, the `list` value will be modified to the `tl` of the
/// BEAM list, and the return value will be the BEAM term.
///
pub fn get_head_and_iter(environment: env, list: *term) !term {
    var head: term = undefined;
    return if (0 != nifApi("enif_get_list_cell")(environment, list.*, &head, list)) head else Error.@"Function clause error";
}

///////////////////////////////////////////////////////////////////////////////
// booleans

/// Converts an BEAM `t:boolean/0` into a Zig `bool`.
///
/// May potentially raise an out of memory error, as it must make an allocation
/// to perform its conversion.
pub fn get_bool(environment: env, val: term) !bool {
    const str = try get_atom_slice(environment, val);
    defer allocator.free(str);
    if (std.mem.eql(u8, "true", str)) return true;
    if (std.mem.eql(u8, "false", str)) return false;
    return Error.@"Fail to get boolean";
}

///////////////////////////////////////////////////////////////////////////////
// syntactic sugar: makes
///////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////
// generic

/// A helper for marshalling values from Zig back into the runtime.  Use this
/// function if you need support for Zig generics.
///
/// supported types:
/// - `c_int`
/// - `c_long`
/// - `isize`
/// - `usize`
/// - `u8`
/// - `i32`
/// - `i64`
/// - `f16`
/// - `f32`
/// - `f64`
pub fn make(comptime T: type, environment: env, val: T) !term {
    if (T == ?*anyopaque) return make_u64(environment, @intFromPtr(val));
    inline for (.{ bool, u8, u16, u32, u64, c_int, c_uint, c_long, c_ulong, isize, usize, i8, i16, i32, i64, f16, f32, f64 }) |Value| {
        if (T == Value) return @field(@This(), "make_" ++ @typeName(Value))(environment, val);
    }
    return Error.@"Function clause error";
}

/// converts a char (`u8`) value into a BEAM `t:integer/0`.
pub const make_u8 = Number(u8, c_int, "int", "uint").make;

/// converts a unsigned (`u16`) value into a BEAM `t:integer/0`.
pub const make_u16 = Number(u16, c_int, "int", "uint").make;

/// converts a unsigned (`u32`) value into a BEAM `t:integer/0`.
pub const make_u32 = Number(u32, c_uint, "uint", "uint").make;

/// converts a unsigned (`u64`) value into a BEAM `t:integer/0`.
pub const make_u64 = Number(u64, u64, "uint64", "uint64").make;

/// converts a `c_int` value into a BEAM `t:integer/0`.
pub const make_c_int = Number(c_int, c_int, "int", "int").make;

/// converts a `c_uint` value into a BEAM `t:integer/0`.
pub const make_c_uint = Number(c_uint, c_uint, "uint", "uint").make;

/// converts a `c_long` value into a BEAM `t:integer/0`.
pub const make_c_long = Number(c_long, c_long, "long", "long").make;

/// converts a `c_ulong` value into a BEAM `t:integer/0`.
pub const make_c_ulong = Number(c_ulong, c_ulong, "ulong", "ulong").make;

/// converts an `i8` value into a BEAM `t:integer/0`.
pub const make_i8 = Number(i8, c_int, "int", "int").make;

/// converts an `i16` value into a BEAM `t:integer/0`.
pub const make_i16 = Number(i16, c_int, "int", "int").make;

/// converts an `isize` value into a BEAM `t:integer/0`.
pub const make_isize = Number(isize, i64, "int64", "int64").make;

/// converts a `usize` value into a BEAM `t:integer/0`.
pub const make_usize = Number(usize, u64, "uint64", "uint64").make;

/// converts an `i32` value into a BEAM `t:integer/0`.
pub const make_i32 = Number(i32, c_int, "int", "int").make;

/// converts an `i64` value into a BEAM `t:integer/0`.
pub const make_i64 = Number(i64, i64, "int64", "int64").make;

///////////////////////////////////////////////////////////////////////////////
// floats

/// converts an `f16` value into a BEAM `t:float/0`.
pub const make_f16 = Number(f16, f64, "double", "double").make;

/// converts an `f32` value into a BEAM `t:float/0`.
pub const make_f32 = Number(f32, f64, "double", "double").make;

/// converts an `f64` value into a BEAM `t:float/0`.
pub const make_f64 = Number(f64, f64, "double", "double").make;

///////////////////////////////////////////////////////////////////////////////
// atoms

/// converts a Zig char slice (`[]u8`) into a BEAM `t:atom/0`.
pub fn make_atom(environment: env, atom_str: []const u8) term {
    return nifApi("enif_make_atom_len")(environment, @ptrCast(&atom_str[0]), atom_str.len);
}

///////////////////////////////////////////////////////////////////////////////
// binaries

/// converts a Zig char slice (`[]u8`) into a BEAM `t:binary/0`.
///
/// no memory allocation inside of Zig is performed and the BEAM environment
/// is responsible for the resulting binary.  You are responsible for managing
/// the allocation of the slice.
pub fn make_slice(environment: env, val: []const u8) term {
    var result: e.ERL_NIF_TERM = undefined;

    var bin: [*]u8 = @ptrCast(nifApi("enif_make_new_binary")(environment, val.len, &result));

    for (val, 0..) |_, i| bin[i] = val[i];

    return result;
}

///////////////////////////////////////////////////////////////////////////////
// tuples

/// converts a slice of `term`s into a BEAM `t:tuple/0`.
pub fn make_tuple(environment: env, val: []term) term {
    return nifApi("enif_make_tuple_from_array")(environment, @ptrCast(val.ptr), @intCast(val.len));
}

///////////////////////////////////////////////////////////////////////////////
// lists

/// converts a slice of `term`s into a BEAM `t:list/0`.
pub fn make_term_list(environment: env, val: []term) term {
    return nifApi("enif_make_list_from_array")(environment, @ptrCast(val.ptr), @intCast(val.len));
}

///////////////////////////////////////////////////////////////////////////////
// list-generic

///////////////////////////////////////////////////////////////////////////////
// special atoms

/// converts a `bool` value into a `t:boolean/0` value.
pub fn make_bool(environment: env, val: bool) term {
    return if (val) nifApi("enif_make_atom")(environment, "true") else nifApi("enif_make_atom")(environment, "false");
}

/// creates a beam `nil` value.
pub fn make_nil(environment: env) term {
    return nifApi("enif_make_atom")(environment, "nil");
}

/// creates a beam `ok` value.
pub fn make_ok(environment: env) term {
    return nifApi("enif_make_atom")(environment, "ok");
}

/// creates a beam `error` value.
pub fn make_error(environment: env) term {
    return nifApi("enif_make_atom")(environment, "error");
}

///////////////////////////////////////////////////////////////////////////////
// ok and error tuples

/// A helper to make `{:ok, binary}` terms from slices
pub fn make_ok_binary(environment: env, val: []const u8) term {
    return make_ok_term(environment, make_slice(environment, val));
}

/// A helper to make `{:ok, term}` terms in general
pub fn make_ok_term(environment: env, val: term) term {
    return nifApi("enif_make_tuple")(environment, 2, make_ok(environment), val);
}

/// A helper to make `{:error, atom}` terms from slices
pub fn make_error_atom(environment: env, val: []const u8) term {
    return make_error_term(environment, make_atom(environment, val));
}

/// A helper to make `{:error, binary}` terms from slices
pub fn make_error_binary(environment: env, val: []const u8) term {
    return make_error_term(environment, make_slice(environment, val));
}

/// A helper to make `{:error, term}` terms in general
pub fn make_error_term(environment: env, val: term) term {
    return nifApi("enif_make_tuple")(environment, 2, make_error(environment), val);
}

///////////////////////////////////////////////////////////////////////////////
// refs

///////////////////////////////////////////////////////////////////////////////
// resources

pub const resource_type = ?*e.ErlNifResourceType;

pub fn open_resource_type(environment: env, name: [*c]const u8, dtor: e.ErlNifResourceDtor) resource_type {
    return nifApi("enif_open_resource_type")(environment, null, name, dtor, e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER, null);
}

///////////////////////////////////////////////////////////////////////////////
// errors, etc.

pub const CallErrorContext = struct {
    message: []const u8,
    reason: []const u8,
    phase: []const u8,
    function: []const u8,
    arity: usize,
    argument_index: ?usize = null,
    expected: ?[]const u8 = null,
    native_error: ?anyerror = null,
};

fn put_exception_field(env_: env, exception: *term, comptime key: []const u8, value: term) void {
    _ = nifApi("enif_make_map_put")(env_, exception.*, make_atom(env_, key), value, exception);
}

fn optional_slice(env_: env, value: ?[]const u8) term {
    return if (value) |slice| make_slice(env_, slice) else make_nil(env_);
}

fn optional_error(env_: env, value: ?anyerror) term {
    return if (value) |err| make_slice(env_, @errorName(err)) else make_nil(env_);
}

pub fn make_call_error(env_: env, context: CallErrorContext) term {
    var exception = nifApi("enif_make_new_map")(env_);
    put_exception_field(env_, &exception, "__struct__", make_atom(env_, "Elixir.Kinda.CallError"));
    put_exception_field(env_, &exception, "__exception__", make_bool(env_, true));
    put_exception_field(env_, &exception, "message", make_slice(env_, context.message));
    put_exception_field(env_, &exception, "reason", make_atom(env_, context.reason));
    put_exception_field(env_, &exception, "phase", make_atom(env_, context.phase));
    put_exception_field(env_, &exception, "function", make_slice(env_, context.function));
    put_exception_field(env_, &exception, "arity", nifApi("enif_make_uint64")(env_, context.arity));
    put_exception_field(
        env_,
        &exception,
        "argument_index",
        if (context.argument_index) |index| nifApi("enif_make_uint64")(env_, index) else make_nil(env_),
    );
    put_exception_field(env_, &exception, "argument_name", make_nil(env_));
    put_exception_field(env_, &exception, "expected", optional_slice(env_, context.expected));
    put_exception_field(env_, &exception, "actual", make_nil(env_));
    put_exception_field(env_, &exception, "native_error", optional_error(env_, context.native_error));
    return exception;
}

pub fn raise_call_error(env_: env, context: CallErrorContext) term {
    return nifApi("enif_raise_exception")(env_, make_call_error(env_, context));
}

pub fn is_nil2(environment: env, val: term) bool {
    return nifApi("enif_is_identical")(val, make_nil(environment)) != 0;
}

pub fn fetch_resource(comptime T: type, environment: env, res_typ: resource_type, res_trm: term) !T {
    var obj: ?*anyopaque = null;
    if (0 == nifApi("enif_get_resource")(environment, res_trm, res_typ, @ptrCast(&obj))) return try get(T, environment, res_trm);
    const val: *T = @ptrCast(@alignCast(obj orelse return Error.@"Fail to fetch resource"));
    return val.*;
}

pub fn fetch_resource_ptr(comptime PtrT: type, environment: env, res_typ: resource_type, res_trm: term) !PtrT {
    var obj: PtrT = undefined;
    if (0 == nifApi("enif_get_resource")(environment, res_trm, res_typ, @ptrCast(&obj))) return Error.@"Fail to fetch resource ptr";
    return obj;
}

/// A retained native reference to a BEAM resource object.
///
/// Use this when one resource contains a pointer to another resource and must
/// keep its parent alive independently of the parent's Erlang term. `init`
/// acquires one native reference and `deinit` releases it. The reference owns
/// that retain and must not be copied into multiple independently-deinitialized
/// values.
pub fn ResourceRef(comptime T: type) type {
    return struct {
        const Self = @This();

        resource: ?*T = null,

        pub fn init(resource: *T) Self {
            nifApi("enif_keep_resource")(resource);
            return .{ .resource = resource };
        }

        pub fn get(reference: *const Self) *T {
            return reference.resource orelse @panic("accessed a released resource reference");
        }

        pub fn deinit(reference: *Self) void {
            const resource = reference.resource orelse return;
            reference.resource = null;
            nifApi("enif_release_resource")(resource);
        }
    };
}

/// Turns the caller-owned reference returned by `enif_alloc_resource` into a
/// BEAM-owned resource term. `enif_make_resource` adds the term reference; the
/// original native reference must still be released so the destructor can run
/// after the term becomes unreachable.
fn make_resource_term(environment: env, resource: *anyopaque) term {
    const result = nifApi("enif_make_resource")(environment, resource);
    nifApi("enif_release_resource")(resource);
    return result;
}

// res_typ should be opened resource type of the array resource
pub fn get_resource_array_from_list(comptime ElementType: type, environment: env, resource_type_element: resource_type, resource_type_array: resource_type, list: term) !term {
    const size = try get_list_length(environment, list);

    const U8Ptr = [*c]u8;
    switch (@typeInfo(ElementType)) {
        .@"struct" => |s| {
            if (s.layout != .@"extern") return Error.@"Fail to fetch resource list element";
        },
        else => {},
    }
    const ArrayPtr = [*c]ElementType;
    const ptr = nifApi("enif_alloc_resource")(resource_type_array, @sizeOf(ArrayPtr) + size * @sizeOf(ElementType)) orelse
        return Error.@"Fail to make array resource";
    errdefer nifApi("enif_release_resource")(ptr);
    var data_ptr: ArrayPtr = undefined;
    const obj: *ArrayPtr = @ptrCast(@alignCast(ptr));
    data_ptr = @ptrCast(@alignCast(@as(U8Ptr, @ptrCast(ptr)) + @sizeOf(ArrayPtr)));
    if (size > 0) {
        obj.* = data_ptr;
    } else {
        obj.* = null;
    }
    var idx: usize = 0;
    var head: term = undefined;
    var movable_list = list;

    while (idx < size) {
        head = try get_head_and_iter(environment, &movable_list);
        if (fetch_resource(ElementType, environment, resource_type_element, head)) |value| {
            data_ptr[idx] = value;
        } else |_| {
            return Error.@"Fail to fetch resource list element";
        }
        idx += 1;
    }
    return make_resource_term(environment, ptr);
}

const mem = @import("std").mem;

pub fn get_resource_array_from_binary(environment: env, resource_type_array: resource_type, binary_term: term) !term {
    const RType = [*c]u8;
    var bin: binary = undefined;
    if (0 == nifApi("enif_inspect_binary")(environment, binary_term, &bin)) return Error.@"Fail to inspect resource binary";
    const ptr = nifApi("enif_alloc_resource")(resource_type_array, @sizeOf(RType) + bin.size) orelse
        return Error.@"Fail to make array resource";
    const obj: *RType = @ptrCast(@alignCast(ptr));
    const real_binary: RType = @ptrCast(@alignCast(@as([*c]u8, @ptrCast(ptr)) + @sizeOf(RType)));
    obj.* = real_binary;
    mem.copyForwards(u8, real_binary[0..bin.size], bin.data[0..bin.size]);
    return make_resource_term(environment, ptr);
}

// the term could be:
// - list of element resource
// - list of primitives
// - binary
pub fn get_resource_array(comptime ElementType: type, environment: env, resource_type_element: resource_type, resource_type_array: resource_type, data: term) !term {
    return get_resource_array_from_list(ElementType, environment, resource_type_element, resource_type_array, data) catch
        get_resource_array_from_binary(environment, resource_type_array, data) catch Error.@"Function clause error";
}
pub fn get_resource_ptr_from_term(environment: env, comptime PtrType: type, element_resource_type: resource_type, ptr_resource_type: resource_type, element: term) !term {
    const ptr = nifApi("enif_alloc_resource")(ptr_resource_type, @sizeOf(PtrType)) orelse
        return Error.@"Fail to make ptr resource";
    errdefer nifApi("enif_release_resource")(ptr);
    const obj: *PtrType = @ptrCast(@alignCast(ptr));
    obj.* = try fetch_resource_ptr(PtrType, environment, element_resource_type, element);
    return make_resource_term(environment, ptr);
}

pub fn make_resource(environment: env, value: anytype, rst: resource_type) !term {
    const RType = @TypeOf(value);
    const ptr = nifApi("enif_alloc_resource")(rst, @sizeOf(RType)) orelse
        return Error.@"Fail to make resource";
    const obj: *RType = @ptrCast(@alignCast(ptr));
    obj.* = value;
    return make_resource_term(environment, ptr);
}

pub export fn destroy_do_nothing(_: env, _: ?*anyopaque) void {}
