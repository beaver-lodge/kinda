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

const e = @import("erl_nif");
const std = @import("std");
const builtin = @import("builtin");
pub const print = @import("std").debug.print;

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
/// currently does not release memory that is resized.  For this behaviour, use
/// use `beam.general_purpose_allocator`.
///
/// not threadsafe.  for a threadsafe allocator, use `beam.general_purpose_allocator`
pub const allocator = raw_beam_allocator;

pub const MAX_ALIGN = 8;

const raw_beam_allocator = Allocator{
    .ptr = undefined,
    .vtable = &raw_beam_allocator_vtable,
};
const raw_beam_allocator_vtable = Allocator.VTable{
    .alloc = raw_beam_alloc,
    .resize = raw_beam_resize,
    .free = raw_beam_free,
};

fn raw_beam_alloc(_: *anyopaque, len: usize, ptr_align: u8, _: usize) ?[*]u8 {
    if (ptr_align > MAX_ALIGN) {
        return null;
    }
    const ptr = e.enif_alloc(len) orelse return null;
    return @as([*]u8, @ptrCast(ptr));
}

fn raw_beam_resize(_: *anyopaque, buf: []u8, _: u8, new_len: usize, _: usize) bool {
    if (new_len == 0) {
        e.enif_free(buf.ptr);
        return true;
    }
    if (new_len <= buf.len) {
        return true;
    }
    return false;
}

fn raw_beam_free(_: *anyopaque, buf: []u8, _: u8, _: usize) void {
    e.enif_free(buf.ptr);
}

/// !value
/// provides a BEAM allocator that can perform allocations with greater
/// alignment than the machine word.  Note that this comes at the cost
/// of some memory to store important metadata.
///
/// currently does not release memory that is resized.  For this behaviour
/// use `beam.general_purpose_allocator`.
///
/// not threadsafe.  for a threadsafe allocator, use `beam.general_purpose_allocator`
pub const large_allocator = large_beam_allocator;

const large_beam_allocator = Allocator{
    .ptr = undefined,
    .vtable = &large_beam_allocator_vtable,
};
const large_beam_allocator_vtable = Allocator.VTable{
    .alloc = large_beam_alloc,
    .resize = large_beam_resize,
    .free = Allocator.NoOpFree(anyopaque).noOpFree,
};

fn large_beam_alloc(_: *anyopaque, len: usize, alignment: u29, len_align: u29, return_address: usize) error{OutOfMemory}![]u8 {
    var ptr = try alignedAlloc(len, alignment, len_align, return_address);
    if (len_align == 0) {
        return ptr[0..len];
    }
    return ptr[0..std.mem.alignBackwardAnyAlign(len, len_align)];
}

fn large_beam_resize(
    _: *anyopaque,
    buf: []u8,
    buf_align: u29,
    new_len: usize,
    len_align: u29,
    _: usize,
) ?usize {
    if (new_len > buf.len) {
        return null;
    }
    if (new_len == 0) {
        return alignedFree(buf, buf_align);
    }
    if (len_align == 0) {
        return new_len;
    }
    return std.mem.alignBackwardAnyAlign(new_len, len_align);
}

fn alignedAlloc(len: usize, alignment: u29, _: u29, _: usize) ![*]u8 {
    const safe_len = safeLen(len, alignment);
    const alloc_slice: []u8 = try allocator.allocAdvanced(u8, MAX_ALIGN, safe_len, std.mem.Allocator.Exact.exact);

    const unaligned_addr = @intFromPtr(alloc_slice.ptr);
    const aligned_addr = reAlign(unaligned_addr, alignment);

    getPtrPtr(aligned_addr).* = unaligned_addr;
    return aligned_addr;
}

fn alignedFree(buf: []u8, alignment: u29) usize {
    const ptr = getPtrPtr(buf.ptr).*;
    allocator.free(@as([*]u8, @ptrFromInt(ptr))[0..safeLen(buf.len, alignment)]);
    return 0;
}

fn reAlign(unaligned_addr: usize, alignment: u29) [*]u8 {
    return @ptrFromInt(std.mem.alignForward(unaligned_addr + @sizeOf(usize), alignment));
}

fn safeLen(len: usize, alignment: u29) usize {
    return len + alignment - @sizeOf(usize) + MAX_ALIGN;
}

fn getPtrPtr(aligned_ptr: [*]u8) *usize {
    return @ptrFromInt(@intFromPtr(aligned_ptr) - @sizeOf(usize));
}

/// !value
/// wraps the zig GeneralPurposeAllocator into the standard BEAM allocator.
var general_purpose_allocator_instance = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){
    .backing_allocator = large_allocator,
};

pub var general_purpose_allocator = general_purpose_allocator_instance.allocator();

///////////////////////////////////////////////////////////////////////////////
// syntactic sugar: important elixir terms
///////////////////////////////////////////////////////////////////////////////

/// errors for nif translation
pub const Error = error{
    /// Translates to Elixir `FunctionClauseError`.
    ///
    /// This is the default mechanism for reporting that a Zigler nif function has
    /// been incorrectly passed a value from the Elixir BEAM runtime.  This is very
    /// important, as Zig is statically typed.
    ///
    /// support for users to be able to throw this value in their own Zig functions
    /// is forthcoming.
    FunctionClauseError,
};

/// errors for launching nif errors
/// LaunchError Occurs when there's a problem launching a threaded nif.
pub const ThreadError = error{LaunchError};

/// syntactic sugar for the BEAM environment.  Note that the `env` type
/// encapsulates the pointer, since you will almost always be passing this
/// pointer to an opaque struct around without accessing it.
pub const env = ?*e.ErlNifEnv;

/// syntactic sugar for the BEAM term struct (`e.ErlNifTerm`)
pub const term = e.ErlNifTerm;

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
    switch (T) {
        c_int => return get_c_int(env_, value),
        c_uint => return get_c_uint(env_, value),
        c_long => return get_c_long(env_, value),
        isize => return get_isize(env_, value),
        usize => return get_usize(env_, value),
        u8 => return get_u8(env_, value),
        u16 => return get_u16(env_, value),
        u32 => return get_u32(env_, value),
        u64 => return get_u64(env_, value),
        i32 => return get_i32(env_, value),
        i64 => return get_i64(env_, value),
        f16 => return get_f16(env_, value),
        f32 => return get_f32(env_, value),
        f64 => return get_f64(env_, value),
        bool => return get_bool(env_, value),
        else => return Error.FunctionClauseError,
    }
}

///////////////////////////////////////////////////////////////////////////////
// ints

/// Takes a BEAM int term and returns a `c_int` value.  Should only be used for
/// C interop with Zig functions.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_c_int(environment: env, src_term: term) !c_int {
    var result: c_int = undefined;
    if (0 != e.enif_get_int(environment, src_term, &result)) {
        return result;
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns a `c_uint` value.  Should only be used for
/// C interop with Zig functions.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_c_uint(environment: env, src_term: term) !c_uint {
    var result: c_uint = undefined;
    if (0 != e.enif_get_uint(environment, src_term, &result)) {
        return result;
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns a `c_long` value.  Should only be used
/// for C interop with Zig functions.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_c_long(environment: env, src_term: term) !c_long {
    var result: c_long = undefined;
    if (0 != e.enif_get_long(environment, src_term, &result)) {
        return result;
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns a `c_ulong` value.  Should only be used
/// for C interop with Zig functions.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_c_ulong(environment: env, src_term: term) !c_ulong {
    var result: c_ulong = undefined;
    if (0 != e.enif_get_ulong(environment, src_term, &result)) {
        return result;
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns a `isize` value.  Should only be used
/// for C interop.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_isize(environment: env, src_term: term) !isize {
    var result: i64 = undefined;
    if (0 != e.enif_get_long(environment, src_term, @ptrCast(&result))) {
        return @intCast(result);
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns a `usize` value.  Zig idiomatically uses
/// `usize` for its size values, so typically you should be using this function.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_usize(environment: env, src_term: term) !usize {
    var result: i64 = undefined;
    if (0 != e.enif_get_long(environment, src_term, @ptrCast(&result))) {
        return @intCast(result);
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns a `u8` value.
///
/// Note that this conversion function checks to make sure it's in range
/// (`0..255`).
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_u8(environment: env, src_term: term) !u8 {
    var result: c_int = undefined;
    if (0 != e.enif_get_int(environment, src_term, &result)) {
        if ((result >= 0) and (result <= 0xFF)) {
            return @intCast(result);
        } else {
            return Error.FunctionClauseError;
        }
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns a `u16` value.
///
/// Note that this conversion function checks to make sure it's in range
/// (`0..65535`).
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_u16(environment: env, src_term: term) !u16 {
    var result: c_int = undefined;
    if (0 != e.enif_get_int(environment, src_term, &result)) {
        if ((result >= 0) and (result <= 0xFFFF)) {
            return @intCast(result);
        } else {
            return Error.FunctionClauseError;
        }
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns a `u32` value.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_u32(environment: env, src_term: term) !u32 {
    var result: c_uint = undefined;
    if (0 != e.enif_get_uint(environment, src_term, &result)) {
        return @intCast(result);
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns a `u64` value.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_u64(environment: env, src_term: term) !u64 {
    var result: c_ulong = undefined;
    if (0 != e.enif_get_ulong(environment, src_term, &result)) {
        return @intCast(result);
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns an `i32` value.
///
/// Note that this conversion function does not currently do range checking.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_i32(environment: env, src_term: term) !i32 {
    var result: c_int = undefined;
    if (0 != e.enif_get_int(environment, src_term, &result)) {
        return @intCast(result);
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM int term and returns an `i64` value.
///
/// Note that this conversion function does not currently do range checking.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:integer/0`
pub fn get_i64(environment: env, src_term: term) !i64 {
    var result: i64 = undefined;
    if (0 != e.enif_get_long(environment, src_term, @ptrCast(&result))) {
        return result;
    } else {
        return Error.FunctionClauseError;
    }
}

///////////////////////////////////////////////////////////////////////////////
// floats

/// Takes a BEAM float term and returns an `f16` value.
///
/// Note that this conversion function does not currently do range checking.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:float/0`
pub fn get_f16(environment: env, src_term: term) !f16 {
    var result: f64 = undefined;
    if (0 != e.enif_get_double(environment, src_term, &result)) {
        return @floatCast(result);
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM float term and returns an `f32` value.
///
/// Note that this conversion function does not currently do range checking.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:float/0`
pub fn get_f32(environment: env, src_term: term) !f32 {
    var result: f64 = undefined;
    if (0 != e.enif_get_double(environment, src_term, &result)) {
        return @floatCast(result);
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes a BEAM float term and returns an `f64` value.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:float/0`
pub fn get_f64(environment: env, src_term: term) !f64 {
    var result: f64 = undefined;
    if (0 != e.enif_get_double(environment, src_term, &result)) {
        return result;
    } else {
        return Error.FunctionClauseError;
    }
}

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
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:atom/0`
pub fn get_atom_slice(environment: env, src_term: atom) ![]u8 {
    return get_atom_slice_alloc(allocator, environment, src_term);
}

/// Takes a BEAM atom term and retrieves it as a slice `[]u8` value, with
/// any allocator.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:atom/0`
pub fn get_atom_slice_alloc(a: Allocator, environment: env, src_term: atom) ![]u8 {
    var len: c_uint = undefined;
    var result: []u8 = undefined;
    if (0 != e.enif_get_atom_length(environment, src_term, @ptrCast(&len), __latin1)) {
        result = try a.alloc(u8, len + 1);

        // pull the value from the beam.
        if (0 != e.enif_get_atom(environment, src_term, @ptrCast(&result[0]), len + 1, __latin1)) {
            // trim the slice, it's the caller's responsibility to free it.
            return result[0..len];
        } else {
            unreachable;
        }
    } else {
        return Error.FunctionClauseError;
    }
}

///////////////////////////////////////////////////////////////////////////////
// binaries

/// shorthand for `e.ErlNifBinary`.
pub const binary = e.ErlNifBinary;

/// Takes an BEAM `t:binary/0` term and retrieves a pointer to the
/// binary data as a Zig c-string (`[*c]u8`).  No memory is allocated for
/// this operation.
///
/// Should only be used for c interop functions.
///
/// *Note*: this function could have unexpected results if your BEAM binary
/// contains any zero byte values.  Always use `get_char_slice/2` when
/// C-interop is not necessary.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:binary/0`
pub fn get_c_string(environment: env, src_term: term) ![*c]u8 {
    var bin: binary = undefined;
    if (0 != e.enif_inspect_binary(environment, src_term, &bin)) {
        return bin.data;
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes an BEAM `t:binary/0` term and retrieves it as a Zig character slice
/// (`[]u8`)  No memory is allocated for this operation.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:binary/0`
pub fn get_char_slice(environment: env, src_term: term) ![]u8 {
    var bin: binary = undefined;

    if (0 != e.enif_inspect_binary(environment, src_term, &bin)) {
        return bin.data[0..bin.size];
    } else {
        return Error.FunctionClauseError;
    }
}

/// Takes an BEAM `t:binary/0` term and returns the corresponding
/// `binary` struct.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:binary/0`
pub fn get_binary(environment: env, src_term: term) !binary {
    var bin: binary = undefined;
    if (0 != e.enif_inspect_binary(environment, src_term, &bin)) {
        return bin;
    } else {
        return Error.FunctionClauseError;
    }
}

///////////////////////////////////////////////////////////////////////////////
// pids

/// shorthand for `e.ErlNifPid`.
pub const pid = e.ErlNifPid;

/// Takes an BEAM `t:pid/0` term and returns the corresponding `pid`
/// struct.
///
/// Note that this is a fairly opaque struct and you're on your
/// own as to what you can do with this (for now), except as a argument
/// for the `e.enif_send` function.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:pid/0`
pub fn get_pid(environment: env, src_term: term) !pid {
    var result: pid = undefined;
    if (0 != e.enif_get_local_pid(environment, src_term, &result)) {
        return result;
    } else {
        return Error.FunctionClauseError;
    }
}

/// shortcut for `e.enif_self`, marshalling into zig error style.
///
/// returns the pid value if it's env is a process-bound environment, otherwise
/// returns `beam.Error.FunctionClauseError`.
///
/// if you're in a threaded nif, it returns the correct `self` for the process
/// running the wrapped function.  That way, `beam.self()` is safe to use when
/// you swap between different execution modes.
///
/// if you need the process mailbox for the actual spawned thread, use `e.enif_self`
pub threadlocal var self: fn (env) Error!pid = generic_self;

pub fn set_generic_self() void {
    self = generic_self;
}

fn generic_self(environment: env) !pid {
    var p: pid = undefined;
    if (e.enif_self(environment, @ptrCast(&p))) |self_val| {
        return self_val.*;
    } else {
        return Error.FunctionClauseError;
    }
}

// internal-use only.
pub fn set_threaded_self() void {
    self = threaded_self;
}

fn threaded_self(environment: env) !pid {
    if (environment == yield_info.?.environment) {
        return yield_info.?.parent;
    }
    return generic_self(environment);
}

/// shortcut for `e.enif_send`
///
/// returns true if the send is successful, false otherwise.
///
/// NOTE this function assumes a valid BEAM environment.  If you have spawned
/// an OS thread without a BEAM environment, you must use `send_advanced/4`
pub fn send(c_env: env, to_pid: pid, msg: term) bool {
    return (e.enif_send(c_env, &to_pid, null, msg) == 1);
}

/// shortcut for `e.enif_send`
///
/// returns true if the send is successful, false otherwise.
///
/// if you are sending from a thread that does not have a BEAM environment, you
/// should put `null` in both environment variables.
pub fn send_advanced(c_env: env, to_pid: pid, m_env: env, msg: term) bool {
    return (e.enif_send(c_env, &to_pid, m_env, msg) == 1);
}

///////////////////////////////////////////////////////////////////////////////
// tuples

/// Takes an Beam `t:tuple/0` term and returns it as a slice of `term` structs.
/// Does *not* allocate memory for this operation.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:tuple/0`
pub fn get_tuple(environment: env, src_term: term) ![]term {
    var length: c_int = 0;
    var term_list: [*c]term = null;
    if (0 != e.enif_get_tuple(environment, src_term, &length, &term_list)) {
        return term_list[0..(length - 1)];
    } else {
        return Error.FunctionClauseError;
    }
}

///////////////////////////////////////////////////////////////////////////////
// lists

/// Takes a BEAM `t:list/0` term and returns its length.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:list/0`
pub fn get_list_length(environment: env, list: term) !usize {
    var result: c_uint = undefined;
    if (0 != e.enif_get_list_length(environment, list, &result)) {
        return @intCast(result);
    } else {
        return Error.FunctionClauseError;
    }
}

/// Iterates over a BEAM `t:list/0`.
///
/// In this function, the `list` value will be modified to the `tl` of the
/// BEAM list, and the return value will be the BEAM term.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:list/0`
pub fn get_head_and_iter(environment: env, list: *term) !term {
    var head: term = undefined;
    if (0 != e.enif_get_list_cell(environment, list.*, &head, list)) {
        return head;
    } else {
        return Error.FunctionClauseError;
    }
}

/// A generic function which lets you convert a BEAM `t:list/0` of
/// homogeous type into a Zig slice.
///
/// The resulting slice will be allocated using the beam allocator, with
/// ownership passed to the caller.  If you need to use a different allocator,
/// use `get_slice_of_alloc/4`
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:list/0`.
/// Also raises `beam.Error.FunctionClauseError` if any of the terms is
/// incompatible with the internal type
///
/// supported internal types:
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
pub fn get_slice_of(comptime T: type, environment: env, list: term) ![]T {
    return get_slice_of_alloc(T, allocator, environment, list);
}

/// Converts an BEAM `t:list/0` of homogeneous type into a Zig slice, but
/// using any allocator you wish.
///
/// ownership is passed to the caller.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:list/0`.
/// Also raises `beam.Error.FunctionClauseError` if any of the terms is
/// incompatible with the internal type.
///
/// supported internal types:
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
pub fn get_slice_of_alloc(comptime T: type, a: Allocator, environment: env, list: term) ![]T {
    const size = try get_list_length(environment, list);

    var idx: usize = 0;
    var head: term = undefined;

    // allocate memory for the Zig list.
    var result = try a.alloc(T, size);
    var movable_list = list;

    while (idx < size) {
        head = try get_head_and_iter(environment, &movable_list);
        result[idx] = try get(T, environment, head);
        idx += 1;
    }
    errdefer a.free(result);

    return result;
}

///////////////////////////////////////////////////////////////////////////////
// booleans

/// private helper string comparison function
fn str_cmp(comptime ref: []const u8, str: []const u8) bool {
    if (str.len != ref.len) {
        return false;
    }
    for (str, 0..) |item, idx| {
        if (item != ref[idx]) {
            return false;
        }
    }
    return true;
}

const true_slice = "true"[0..];
const false_slice = "false"[0..];
/// Converts an BEAM `t:boolean/0` into a Zig `bool`.
///
/// Raises `beam.Error.FunctionClauseError` if the term is not `t:boolean/0`.
/// May potentially raise an out of memory error, as it must make an allocation
/// to perform its conversion.
pub fn get_bool(environment: env, val: term) !bool {
    var str: []u8 = undefined;
    str = try get_atom_slice(environment, val);
    defer allocator.free(str);

    if (str_cmp(true_slice, str)) {
        return true;
    } else if (str_cmp(false_slice, str)) {
        return false;
    } else {
        return Error.FunctionClauseError;
    }
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
    switch (T) {
        bool => return make_bool(environment, val),
        u8 => return make_u8(environment, val),
        u16 => return make_u16(environment, val),
        u32 => return make_u32(environment, val),
        u64 => return make_u64(environment, val),
        c_int => return make_c_int(environment, val),
        c_uint => return make_c_uint(environment, val),
        c_long => return make_c_long(environment, val),
        c_ulong => return make_c_ulong(environment, val),
        isize => return make_isize(environment, val),
        usize => return make_usize(environment, val),
        i32 => return make_i32(environment, val),
        i64 => return make_i64(environment, val),
        f16 => return make_f16(environment, val),
        f32 => return make_f32(environment, val),
        f64 => return make_f64(environment, val),
        ?*anyopaque => return make_u64(environment, @intFromPtr(val)),
        else => return Error.FunctionClauseError,
    }
}

/// converts a char (`u8`) value into a BEAM `t:integer/0`.
pub fn make_u8(environment: env, chr: u8) term {
    return e.enif_make_uint(environment, @intCast(chr));
}

/// converts a unsigned (`u16`) value into a BEAM `t:integer/0`.
pub fn make_u16(environment: env, val: u16) term {
    return e.enif_make_uint(environment, @intCast(val));
}

/// converts a unsigned (`u32`) value into a BEAM `t:integer/0`.
pub fn make_u32(environment: env, val: u32) term {
    return e.enif_make_uint(environment, @intCast(val));
}

/// converts a unsigned (`u64`) value into a BEAM `t:integer/0`.
pub fn make_u64(environment: env, val: u64) term {
    return e.enif_make_ulong(environment, @intCast(val));
}

/// converts a `c_int` value into a BEAM `t:integer/0`.
pub fn make_c_int(environment: env, val: c_int) term {
    return e.enif_make_int(environment, val);
}

/// converts a `c_uint` value into a BEAM `t:integer/0`.
pub fn make_c_uint(environment: env, val: c_uint) term {
    return e.enif_make_uint(environment, val);
}

/// converts a `c_long` value into a BEAM `t:integer/0`.
pub fn make_c_long(environment: env, val: c_long) term {
    return e.enif_make_long(environment, val);
}

/// converts a `c_ulong` value into a BEAM `t:integer/0`.
pub fn make_c_ulong(environment: env, val: c_ulong) term {
    return e.enif_make_ulong(environment, val);
}

/// converts an `isize` value into a BEAM `t:integer/0`.
pub fn make_isize(environment: env, val: isize) term {
    return e.enif_make_int(environment, @intCast(val));
}

/// converts a `usize` value into a BEAM `t:integer/0`.
pub fn make_usize(environment: env, val: usize) term {
    return e.enif_make_int(environment, @intCast(val));
}

/// converts an `i32` value into a BEAM `t:integer/0`.
pub fn make_i32(environment: env, val: i32) term {
    return e.enif_make_int(environment, @intCast(val));
}

/// converts an `i64` value into a BEAM `t:integer/0`.
pub fn make_i64(environment: env, val: i64) term {
    return e.enif_make_long(environment, @intCast(val));
}

///////////////////////////////////////////////////////////////////////////////
// floats

/// converts an `f16` value into a BEAM `t:float/0`.
pub fn make_f16(environment: env, val: f16) term {
    return e.enif_make_double(environment, @floatCast(val));
}

/// converts an `f32` value into a BEAM `t:float/0`.
pub fn make_f32(environment: env, val: f32) term {
    return e.enif_make_double(environment, @floatCast(val));
}

/// converts an `f64` value into a BEAM `t:float/0`.
pub fn make_f64(environment: env, val: f64) term {
    return e.enif_make_double(environment, val);
}

///////////////////////////////////////////////////////////////////////////////
// atoms

/// converts a Zig char slice (`[]u8`) into a BEAM `t:atom/0`.
pub fn make_atom(environment: env, atom_str: []const u8) term {
    return e.enif_make_atom_len(environment, @ptrCast(&atom_str[0]), atom_str.len);
}

///////////////////////////////////////////////////////////////////////////////
// binaries

/// converts a Zig char slice (`[]u8`) into a BEAM `t:binary/0`.
///
/// no memory allocation inside of Zig is performed and the BEAM environment
/// is responsible for the resulting binary.  You are responsible for managing
/// the allocation of the slice.
pub fn make_slice(environment: env, val: []const u8) term {
    var result: e.ErlNifTerm = undefined;

    var bin: [*]u8 = @ptrCast(e.enif_make_new_binary(environment, val.len, &result));

    for (val, 0..) |_, i| {
        bin[i] = val[i];
    }

    return result;
}

/// converts an c string (`[*c]u8`) into a BEAM `t:binary/0`. Mostly used for
/// c interop.
///
/// no memory allocation inside of Zig is performed and the BEAM environment
/// is responsible for the resulting binary.  You are responsible for managing
/// the allocation of the slice.
pub fn make_c_string(environment: env, val: [*c]const u8) term {
    const result: e.ErlNifTerm = undefined;
    var len: usize = 0;

    // first get the length of the c string.
    for (result, 0..) |chr, i| {
        if (chr == 0) {
            break;
        }
        len = i;
    }

    // punt to the slicing function.
    return make_slice(environment, val[0 .. len + 1]);
}

///////////////////////////////////////////////////////////////////////////////
// tuples

/// converts a slice of `term`s into a BEAM `t:tuple/0`.
pub fn make_tuple(environment: env, val: []term) term {
    return e.enif_make_tuple_from_array(environment, @ptrCast(val.ptr), @intCast(val.len));
}

///////////////////////////////////////////////////////////////////////////////
// lists

/// converts a slice of `term`s into a BEAM `t:list/0`.
pub fn make_term_list(environment: env, val: []term) term {
    return e.enif_make_list_from_array(environment, @ptrCast(val.ptr), @intCast(val.len));
}

/// converts a Zig char slice (`[]u8`) into a BEAM `t:charlist/0`.
pub fn make_charlist(environment: env, val: []const u8) term {
    return e.enif_make_string_len(environment, val, val.len, __latin1);
}

/// converts a c string (`[*c]u8`) into a BEAM `t:charlist/0`.
pub fn make_c_string_charlist(environment: env, val: [*c]const u8) term {
    return e.enif_make_string(environment, val, __latin1);
}

pub fn make_charlist_len(environment: env, val: [*c]const u8, length: usize) term {
    return e.enif_make_string_len(environment, val, length, __latin1);
}

///////////////////////////////////////////////////////////////////////////////
// list-generic

/// A helper to make BEAM lists out of slices of `term`.  Use this function if
/// you need a generic listbuilding function.
///
/// uses the BEAM allocator internally.  If you would like to use a custom
/// allocator, (for example an arena allocator, if you have very long lists),
/// use `make_list_alloc/4`
///
/// supported internal types:
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
pub fn make_list(comptime T: type, environment: env, val: []T) !term {
    return make_list_alloc(T, allocator, environment, val);
}

/// A helper to make a BEAM `t:Kernel.list` out of `term`s, with any allocator.
/// Use this function if you need a generic listbuilding function.
///
/// supported internal types:
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
pub fn make_list_alloc(comptime T: type, a: Allocator, environment: env, val: []T) !term {
    var term_slice: []term = try a.alloc(term, val.len);
    defer a.free(term_slice);

    for (val, 0..) |item, idx| {
        term_slice[idx] = make(T, environment, item);
    }

    return e.enif_make_list_from_array(environment, @ptrCast(&term_slice[0]), @intCast(val.len));
}

/// converts a c_int slice (`[]c_int`) into a BEAM list of `integer/0`.
pub fn make_c_int_list(environment: env, val: []c_int) !term {
    return try make_list(c_int, environment, val);
}

/// converts a c_long slice (`[]c_long`) into a BEAM list of `integer/0`.
pub fn make_c_long_list(environment: env, val: []c_long) !term {
    return try make_list(c_long, environment, val);
}

/// converts an i32 slice (`[]i32`) into a BEAM list of `integer/0`.
pub fn make_i32_list(environment: env, val: []i32) !term {
    return try make_list(i32, environment, val);
}

/// converts an i64 slice (`[]i64`) into a BEAM list of `integer/0`.
pub fn make_i64_list(environment: env, val: []i64) !term {
    return try make_list(i64, environment, val);
}

/// converts an f16 slice (`[]f16`) into a BEAM list of `t:float/0`.
pub fn make_f16_list(environment: env, val: []f16) !term {
    return try make_list(f16, environment, val);
}

/// converts an f32 slice (`[]f32`) into a BEAM list of `t:float/0`.
pub fn make_f32_list(environment: env, val: []f32) !term {
    return try make_list(f32, environment, val);
}

/// converts an f64 slice (`[]f64`) into a BEAM list of `t:float/0`.
pub fn make_f64_list(environment: env, val: []f64) !term {
    return try make_list(f64, environment, val);
}

///////////////////////////////////////////////////////////////////////////////
// special atoms

/// converts a `bool` value into a `t:boolean/0` value.
pub fn make_bool(environment: env, val: bool) term {
    return if (val) e.enif_make_atom(environment, "true") else e.enif_make_atom(environment, "false");
}

/// creates a beam `nil` value.
pub fn make_nil(environment: env) term {
    return e.enif_make_atom(environment, "nil");
}

/// creates a beam `ok` value.
pub fn make_ok(environment: env) term {
    return e.enif_make_atom(environment, "ok");
}

/// creates a beam `error` value.
pub fn make_error(environment: env) term {
    return e.enif_make_atom(environment, "error");
}

///////////////////////////////////////////////////////////////////////////////
// ok and error tuples

/// A helper to make `{:ok, term}` terms from arbitrarily-typed values.
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
///
/// Use `make_ok_term/2` to make ok tuples from generic terms.
/// Use `make_ok_atom/2` to make ok tuples with atom terms from slices.
pub fn make_ok_tuple(comptime T: type, environment: env, val: T) term {
    return make_ok_term(environment, make(T, environment, val));
}

/// A helper to make `{:ok, binary}` terms from slices
pub fn make_ok_binary(environment: env, val: []const u8) term {
    return make_ok_term(environment, make_slice(environment, val));
}

/// A helper to make `{:ok, atom}` terms from slices
pub fn make_ok_atom(environment: env, val: []const u8) term {
    return make_ok_term(environment, make_atom(environment, val));
}

/// A helper to make `{:ok, term}` terms in general
pub fn make_ok_term(environment: env, val: term) term {
    return e.enif_make_tuple(environment, 2, make_ok(environment), val);
}

/// A helper to make `{:error, term}` terms from arbitrarily-typed values.
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
///
/// Use `make_error_term/2` to make error tuples from generic terms.
/// Use `make_error_atom/2` to make atom errors from slices.
pub fn make_error_tuple(comptime T: type, environment: env, val: T) term {
    return make_error_term(environment, make(T, environment, val));
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
    return e.enif_make_tuple(environment, 2, make_error(environment), val);
}

///////////////////////////////////////////////////////////////////////////////
// refs

/// Encapsulates `e.enif_make_ref` and allows it to return a
/// FunctionClauseError.
pub fn make_ref(environment: env) term {
    return e.enif_make_ref(environment);
}

///////////////////////////////////////////////////////////////////////////////
// resources

pub const resource_type = ?*e.ErlNifResourceType;

///////////////////////////////////////////////////////////////////////////////
// yielding NIFs

/// transparently passes information into the yield statement.
pub threadlocal var yield_info: ?*YieldInfo = null;

pub fn Frame(function: anytype) type {
    return struct {
        yield_info: YieldInfo,
        zig_frame: *@Frame(function),
    };
}

pub const YieldError = error{
    LaunchError,
    Cancelled,
};

/// this function is called to tell zigler's scheduler that future rescheduling
/// *or* cancellation is possible at this point.  For threaded nifs, it also
/// serves as a potential cancellation point.
pub fn yield() !void {
    // only suspend if we are inside of a yielding nif
    if (yield_info) |info| { // null, for synchronous nifs.
        if (info.threaded) {
            const should_cancel = @atomicLoad(YieldState, &info.state, .Monotonic) == .Cancelled;
            if (should_cancel) {
                return YieldError.Cancelled;
            }
        } else {
            // must be yielding
            suspend {
                if (info.state == .Cancelled) return YieldError.Cancelled;
                info.yield_frame = @frame();
            }
        }
    }
}

pub const YieldState = enum { Running, Finished, Cancelled, Abandoned };

pub const YieldInfo = struct {
    yield_frame: ?anyframe = null,
    state: YieldState = .Running,
    threaded: bool = false,
    errored: bool = false,
    response: term = undefined,
    parent: pid = undefined,
    environment: env,
};

pub fn set_yield_response(what: term) void {
    yield_info.?.response = what;
}

///////////////////////////////////////////////////////////////////////////////
// errors, etc.

pub fn raise(environment: env, exception: term) term {
    return e.enif_raise_exception(environment, exception);
}

// create a global enomem string, then throw it.
const enomem_slice = "enomem";

/// This function is used to communicate `:enomem` back to the BEAM as an
/// exception.
///
/// The BEAM is potentially OOM-safe, and Zig lets you leverage that.
/// OOM errors from `beam.allocator` can be converted to a generic erlang term
/// that represents an exception.  Returning this from your NIF results in
/// a BEAM throw event.
pub fn raise_enomem(environment: env) term {
    return e.enif_raise_exception(environment, make_atom(environment, enomem_slice));
}

const f_c_e_slice = "function_clause";

/// This function is used to communicate `:function_clause` back to the BEAM as an
/// exception.
///
/// By default Zigler will do argument input checking on value
/// ingress from the dynamic BEAM runtime to the static Zig runtime.
/// You can also use this function to communicate a similar error by returning the
/// resulting term from your NIF.
pub fn raise_function_clause_error(env_: env) term {
    return e.enif_raise_exception(env_, make_atom(env_, f_c_e_slice));
}

const resource_error = "resource_error";

/// This function is used to communicate `:resource_error` back to the BEAM as an
/// exception.
pub fn raise_resource_error(env_: env) term {
    return e.enif_raise_exception(env_, make_atom(env_, resource_error));
}

const assert_slice = "assertion_error";

/// This function is used to communicate `:assertion_error` back to the BEAM as an
/// exception.
///
/// Used when running Zigtests, when trapping `beam.AssertionError.AssertionError`.
pub fn raise_assertion_error(env_: env) term {
    return e.enif_raise_exception(env_, make_atom(env_, assert_slice));
}

fn writeStackTraceToBuffer(
    environment: env,
    stack_trace: std.builtin.StackTrace,
) !term {
    const debug_info = std.debug.getSelfDebugInfo() catch |err| {
        std.debug.print("Unable to dump stack trace: Unable to open debug info: {s}. Will dump it to stderr\n", .{@errorName(err)});
        std.debug.dumpStackTrace(stack_trace);
        return err;
    };
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try std.debug.writeStackTrace(stack_trace, &buffer.writer(), allocator, debug_info, std.io.tty.detectConfig(std.io.getStdErr()));
    return make_slice(environment, buffer.items);
}

pub fn make_exception(env_: env, exception_module: []const u8, err: anyerror, error_trace: ?*std.builtin.StackTrace) term {
    const erl_err = make_atom(env_, @errorName(err));
    if (error_trace) |trace| {
        const stack_trace = writeStackTraceToBuffer(env_, trace.*) catch make_nil(env_);
        var exception = e.enif_make_new_map(env_);
        // define the struct
        _ = e.enif_make_map_put(env_, exception, make_atom(env_, "__struct__"), make_atom(env_, exception_module), &exception);
        _ = e.enif_make_map_put(env_, exception, make_atom(env_, "__exception__"), make_bool(env_, true), &exception);
        // define the error
        _ = e.enif_make_map_put(env_, exception, make_atom(env_, "message"), erl_err, &exception);

        // store the error return trace
        _ = e.enif_make_map_put(env_, exception, make_atom(env_, "error_return_trace"), stack_trace, &exception);

        return exception;
    } else {
        return erl_err;
    }
}

pub fn raise_exception(env_: env, exception_module: []const u8, err: anyerror, error_trace: ?*std.builtin.StackTrace) term {
    if (error_trace) |_| {
        return e.enif_raise_exception(env_, make_exception(env_, exception_module, err, error_trace));
    } else {
        return make_nil(env_);
    }
}

/// !value
/// you can use this value to access the BEAM environment of your unit test.
pub threadlocal var test_env: env = undefined;

///////////////////////////////////////////////////////////////////////////////
// NIF LOADING Boilerplate

pub export fn blank_load(_: env, _: [*c]?*anyopaque, _: term) c_int {
    return 0;
}

pub export fn blank_upgrade(_: env, _: [*c]?*anyopaque, _: [*c]?*anyopaque, _: term) c_int {
    return 0;
}

const nil_slice = "nil"[0..];
pub fn is_nil(environment: env, val: term) !bool {
    var str: []u8 = undefined;
    str = try get_atom_slice(environment, val);
    defer allocator.free(str);
    if (str_cmp(nil_slice, str)) {
        return true;
    } else {
        return false;
    }
}

pub fn is_nil2(environment: env, val: term) bool {
    return is_nil(environment, val) catch false;
}

pub fn fetch_resource(comptime T: type, environment: env, res_typ: resource_type, res_trm: term) !T {
    var obj: ?*anyopaque = null;
    if (0 == e.enif_get_resource(environment, res_trm, res_typ, @ptrCast(&obj))) {
        return try get(T, environment, res_trm);
    }
    if (obj != null) {
        const val: *T = @ptrCast(@alignCast(obj));
        return val.*;
    } else {
        print("fail to get resource of type: {}\n", .{T});
        return Error.FunctionClauseError;
    }
}

pub fn fetch_resource_wrapped(comptime T: type, environment: env, arg: term) !T {
    return fetch_resource(T, environment, T.resource_type, arg);
}

pub fn fetch_ptr_resource_wrapped(comptime T: type, environment: env, arg: term) !*T {
    return fetch_resource(*T, environment, T.resource_type, arg);
}

pub fn fetch_resource_ptr(comptime T: type, environment: env, res_typ: resource_type, res_trm: term) !*T {
    var obj: ?*T = undefined;
    if (0 == e.enif_get_resource(environment, res_trm, res_typ, @ptrCast(&obj))) {
        return Error.FunctionClauseError;
    }
    if (obj != null) {
        return obj.?;
    } else {
        print("fail to get ptr of resource of type: {}\n", .{T});
        return Error.FunctionClauseError;
    }
}

// res_typ should be opened resource type of the array resource
pub fn get_resource_array_from_list(comptime ElementType: type, environment: env, resource_type_element: resource_type, resource_type_array: resource_type, list: term) !term {
    const size = try get_list_length(environment, list);

    const U8Ptr = [*c]u8;
    const ArrayPtr = [*c]ElementType;
    const ptr: ?*anyopaque = e.enif_alloc_resource(resource_type_array, @sizeOf(ArrayPtr) + size * @sizeOf(ElementType));
    var data_ptr: ArrayPtr = undefined;
    if (ptr == null) {
        unreachable();
    } else {
        var obj: *ArrayPtr = undefined;
        obj = @ptrCast(@alignCast(ptr));
        data_ptr = @ptrCast(@alignCast(@as(U8Ptr, @ptrCast(ptr)) + @sizeOf(ArrayPtr)));
        if (size > 0) {
            obj.* = data_ptr;
        } else {
            obj.* = 0;
        }
    }
    var idx: usize = 0;
    var head: term = undefined;
    var movable_list = list;

    while (idx < size) {
        head = try get_head_and_iter(environment, &movable_list);
        if (fetch_resource(ElementType, environment, resource_type_element, head)) |value| {
            data_ptr[idx] = value;
        } else |err| {
            print("[Beaver] fail to get element #{} in list, expect resource of type: {s}\n", .{ idx, @typeName(ElementType) });
            return err;
        }
        idx += 1;
    }
    return e.enif_make_resource(environment, ptr);
}

const mem = @import("std").mem;

pub fn get_resource_array_from_binary(environment: env, resource_type_array: resource_type, binary_term: term) !term {
    const RType = [*c]u8;
    var bin: binary = undefined;
    if (0 == e.enif_inspect_binary(environment, binary_term, &bin)) {
        return Error.FunctionClauseError;
    }
    const ptr: ?*anyopaque = e.enif_alloc_resource(resource_type_array, @sizeOf(RType) + bin.size);
    var obj: *RType = undefined;
    var real_binary: RType = undefined;
    if (ptr == null) {
        unreachable();
    } else {
        obj = @ptrCast(@alignCast(ptr));
        real_binary = @ptrCast(@alignCast(ptr));
        real_binary += @sizeOf(RType);
        obj.* = real_binary;
    }
    mem.copyForwards(u8, real_binary[0..bin.size], bin.data[0..bin.size]);
    return e.enif_make_resource(environment, ptr);
}

// the term could be:
// - list of element resource
// - list of primitives
// - binary
pub fn get_resource_array(comptime ElementType: type, environment: env, resource_type_element: resource_type, resource_type_array: resource_type, data: term) !term {
    if (get_resource_array_from_list(ElementType, environment, resource_type_element, resource_type_array, data)) |value| {
        return value;
    } else |_| {
        if (get_resource_array_from_binary(environment, resource_type_array, data)) |value| {
            return value;
        } else |_| {
            return Error.FunctionClauseError;
        }
    }
}
pub fn get_resource_ptr_from_term(comptime ElementType: type, environment: env, resource_type_element: resource_type, resource_type_ptr: resource_type, element: term) !term {
    const RType = [*c]ElementType;
    const ptr: ?*anyopaque = e.enif_alloc_resource(resource_type_ptr, @sizeOf(RType));
    var obj: *RType = undefined;
    obj = @ptrCast(@alignCast(ptr));
    if (ptr == null) {
        unreachable();
    } else {
        obj.* = try fetch_resource_ptr(ElementType, environment, resource_type_element, element);
    }
    return e.enif_make_resource(environment, ptr);
}

pub fn make_resource(environment: env, value: anytype, rst: resource_type) !term {
    const RType = @TypeOf(value);
    const ptr: ?*anyopaque = e.enif_alloc_resource(rst, @sizeOf(RType));
    var obj: *RType = undefined;
    if (ptr == null) {
        return Error.FunctionClauseError;
    } else {
        obj = @ptrCast(@alignCast(ptr));
        obj.* = value;
    }
    return e.enif_make_resource(environment, ptr);
}

pub fn make_resource_wrapped(environment: env, value: anytype) !term {
    return make_resource(environment, value, @TypeOf(value).resource_type);
}

pub fn make_ptr_resource_wrapped(environment: env, ptr: anytype) !term {
    return make_resource(environment, ptr, @TypeOf(ptr.*).resource_type);
}

pub export fn destroy_do_nothing(_: env, _: ?*anyopaque) void {}
pub fn open_resource_wrapped(environment: env, comptime T: type) void {
    T.resource_type = e.enif_open_resource_type(environment, null, T.resource_name, destroy_do_nothing, e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER, null);
}
