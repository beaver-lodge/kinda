pub const beam = @import("beam.zig");
const builtin = @import("builtin");
pub const erl_nif = @cImport({
    @cInclude("erl_nif.h");
});
const e = erl_nif;
const std = @import("std");
pub const result = @import("result.zig");
pub const callback_runtime = @import("callback_runtime.zig");
pub const callback_adapter = @import("callback_adapter.zig");

fn nifApiType(comptime name: []const u8) type {
    const function_type = if (builtin.os.tag == .windows)
        @TypeOf(@field(e.WinDynNifCallbacks, name))
    else
        @TypeOf(@field(e, name));

    return switch (@typeInfo(function_type)) {
        .optional => |optional| optional.child,
        else => function_type,
    };
}

pub inline fn nifApi(comptime name: []const u8) nifApiType(name) {
    if (builtin.os.tag == .windows) {
        return @field(e.WinDynNifCallbacks, name).?;
    }

    return @field(e, name);
}

// a function to make a resource term from a u8 slice.
const OpaqueMaker: type = fn (beam.env, []u8) beam.term;
pub const OpaqueStructType = struct {
    const Accessor: type = struct { maker: OpaqueMaker, offset: usize };
    const ArrayType = ?*anyopaque;
    const PtrType = ?*anyopaque;
    storage: std.array_list.AlignedManaged(u8, null) = std.array_list.Managed(u8).init(beam.allocator),
    finalized: bool, // if it is finalized, can't append more fields to it. Only finalized struct can be addressed.
    accessors: std.ArrayList(Accessor),
};

pub const OpaqueField = extern struct {
    storage: std.array_list.AlignedManaged(u8, null),
    maker: type = OpaqueMaker,
};

pub const Internal = struct {
    pub const OpaquePtr: type = ResourceKind(?*anyopaque, "Kinda.Internal.OpaquePtr");
    pub const OpaqueArray: type = ResourceKind(?*const anyopaque, "Kinda.Internal.OpaqueArray");
    pub const USize: type = ResourceKind(usize, "Kinda.Internal.USize");
    pub const OpaqueStruct: type = ResourceKind(OpaqueStructType, "Kinda.Internal.OpaqueStruct");
};

/// A single ERTS resource type slot owned by a `ResourceKind`: the
/// `resource` value, its `Ptr` wrapper, or its `Array` wrapper. Describing all
/// three slots uniformly lets `open_all` iterate them and lets downstream NIF
/// libraries build one name -> handle registry for cross-partition resource
/// sharing without reopening (which would create distinct resource types).
pub const ResourceSlot = struct {
    name: []const u8,
    t: *beam.resource_type,
    dtor: e.ErlNifResourceDtor,
};

pub const ResourceOpenMode = enum {
    primary,
    all,
};

pub const ResourceRegistration = struct {
    kind: type,
    open: ResourceOpenMode = .primary,
};

/// Checks the static shape shared by native resources that defer closing until
/// their last child is released. The backend supplies its private methods
/// explicitly so the contract does not require public lifecycle hooks or own
/// any runtime behavior.
pub fn validateDeferredCloseParent(comptime Parent: type, comptime contract: anytype) void {
    const Contract = @TypeOf(contract);

    comptime {
        for (.{ "counter", "close", "close_if_unused", "release" }) |field| {
            if (!@hasField(Contract, field)) {
                @compileError("deferred-close contract for " ++ @typeName(Parent) ++ " is missing ." ++ field);
            }
        }

        switch (@typeInfo(Parent)) {
            .@"struct" => {},
            else => @compileError("deferred-close parent must be a struct, got " ++ @typeName(Parent)),
        }

        if (!@hasField(Parent, contract.counter)) {
            @compileError("deferred-close parent " ++ @typeName(Parent) ++ " is missing counter field " ++ contract.counter);
        }

        if (fieldType(Parent, contract.counter) != std.atomic.Value(usize)) {
            @compileError("deferred-close counter " ++ @typeName(Parent) ++ "." ++ contract.counter ++ " must be std.atomic.Value(usize)");
        }

        if (!@hasField(Parent, "close_requested")) {
            @compileError("deferred-close parent " ++ @typeName(Parent) ++ " is missing close_requested");
        }

        if (fieldType(Parent, "close_requested") != std.atomic.Value(bool)) {
            @compileError("deferred-close field " ++ @typeName(Parent) ++ ".close_requested must be std.atomic.Value(bool)");
        }

        const Method = fn (*Parent) void;
        for (.{
            .{ "close", contract.close },
            .{ "close_if_unused", contract.close_if_unused },
            .{ "release", contract.release },
        }) |method| {
            if (@TypeOf(method[1]) != Method) {
                @compileError("deferred-close method " ++ @typeName(Parent) ++ "." ++ method[0] ++ " must accept *" ++ @typeName(Parent) ++ " and return void");
            }
        }
    }
}

fn fieldType(comptime Container: type, comptime name: []const u8) type {
    inline for (@typeInfo(Container).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return field.type;
    }

    @compileError("missing field " ++ @typeName(Container) ++ "." ++ name);
}

/// Opens a fixed set of resource kinds without changing their per-NIF scope.
///
/// Registrations explicitly choose whether only the primary resource type or
/// every generated wrapper slot is public. The registry deliberately owns no
/// global state: every instantiation opens handles in the calling NIF's load
/// environment exactly as the equivalent handwritten calls would.
pub fn ResourceRegistry(comptime registrations: anytype) type {
    comptime {
        for (registrations) |registration| {
            const Registration = @TypeOf(registration);

            if (Registration != ResourceRegistration) {
                @compileError("resource registry entries must be Kinda.ResourceRegistration values");
            }

            if (!@hasDecl(registration.kind, "open") or
                !@hasDecl(registration.kind, "open_all") or
                !@hasDecl(registration.kind, "slots"))
            {
                @compileError("resource registry kind must be created by Kinda.ResourceKind");
            }
        }
    }

    return struct {
        pub fn open(env: beam.env) c_int {
            inline for (registrations) |registration| {
                switch (registration.open) {
                    .primary => registration.kind.open(env),
                    .all => registration.kind.open_all(env),
                }
            }

            inline for (registrations) |registration| {
                const slot_count = switch (registration.open) {
                    .primary => 1,
                    .all => registration.kind.slots.len,
                };

                inline for (registration.kind.slots[0..slot_count]) |slot| {
                    if (slot.t.* == null) return 1;
                }
            }

            return 0;
        }
    };
}

fn EntryPoint(
    comptime initialize: anytype,
    comptime windows_callbacks_target: anytype,
) type {
    return if (builtin.os.tag == .windows) struct {
        var callbacks: e.TWinDynNifCallbacks = undefined;
        const target: ?*e.TWinDynNifCallbacks = windows_callbacks_target;

        fn init(win_callbacks: *const e.TWinDynNifCallbacks) callconv(.c) *const e.ErlNifEntry {
            if (target) |external_callbacks| {
                external_callbacks.* = win_callbacks.*;
            } else {
                callbacks = win_callbacks.*;
            }
            return initialize();
        }

        fn exportSymbols() void {
            if (target == null) {
                @export(&callbacks, .{ .name = "WinDynNifCallbacks" });
            }
            @export(&init, .{ .name = "nif_init" });
        }
    } else struct {
        fn init() callconv(.c) *const e.ErlNifEntry {
            return initialize();
        }

        fn exportSymbols() void {
            @export(&init, .{ .name = "nif_init" });
        }
    };
}

/// Materializes an Erlang NIF function tuple and exports the platform-specific
/// `nif_init` entrypoint. Load, upgrade, and unload callbacks remain explicit
/// backend policy supplied through `spec`. On Windows, a NIF which links a
/// shared enif shim may pass `.windows_callbacks_target` so `nif_init` fills
/// that shim-owned table instead of exporting a private table.
pub fn EntryExports(comptime spec: anytype) type {
    const Spec = @TypeOf(spec);

    comptime {
        for (.{ "name", "nifs", "load" }) |field| {
            if (!@hasField(Spec, field)) {
                @compileError("Kinda.EntryExports spec is missing required field ." ++ field);
            }
        }

        for (spec.nifs) |nif| {
            if (@TypeOf(nif) != e.ErlNifFunc) {
                @compileError("Kinda.EntryExports .nifs must contain ErlNifFunc values");
            }
        }
    }

    const upgrade = if (@hasField(Spec, "upgrade")) spec.upgrade else null;
    const unload = if (@hasField(Spec, "unload")) spec.unload else null;
    const min_erts = if (@hasField(Spec, "min_erts")) spec.min_erts else "erts-15.0";

    return struct {
        pub export var nifs: [spec.nifs.len]e.ErlNifFunc = spec.nifs;

        const entry = e.ErlNifEntry{
            .major = 2,
            .minor = 16,
            .name = spec.name,
            .num_of_funcs = nifs.len,
            .funcs = &nifs[0],
            .load = spec.load,
            .reload = null,
            .upgrade = upgrade,
            .unload = unload,
            .vm_variant = "beam.vanilla",
            .options = 1,
            .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit),
            .min_erts = min_erts,
        };

        fn initialize() *const e.ErlNifEntry {
            return &entry;
        }

        const windows_callbacks_target = if (@hasField(Spec, "windows_callbacks_target"))
            spec.windows_callbacks_target
        else
            null;
        const NifInit = EntryPoint(initialize, windows_callbacks_target);

        comptime {
            NifInit.exportSymbols();
        }
    };
}

/// Exports a platform-specific `nif_init` entrypoint for a NIF table assembled
/// at runtime. The provider is called during `nif_init`, before the load
/// callback, and must return storage whose address remains stable until the NIF
/// is unloaded. On Windows, `.windows_callbacks_target` has the same shared
/// shim semantics as `EntryExports`.
pub fn DynamicEntryExports(comptime spec: anytype) type {
    const Spec = @TypeOf(spec);

    comptime {
        for (.{ "name", "nifs_provider", "load" }) |field| {
            if (!@hasField(Spec, field)) {
                @compileError("Kinda.DynamicEntryExports spec is missing required field ." ++ field);
            }
        }

        const Provider = fn () []e.ErlNifFunc;
        if (@TypeOf(spec.nifs_provider) != Provider) {
            @compileError("Kinda.DynamicEntryExports .nifs_provider must be fn() []ErlNifFunc");
        }
    }

    const upgrade = if (@hasField(Spec, "upgrade")) spec.upgrade else null;
    const unload = if (@hasField(Spec, "unload")) spec.unload else null;
    const min_erts = if (@hasField(Spec, "min_erts")) spec.min_erts else "erts-15.0";

    return struct {
        var entry: e.ErlNifEntry = undefined;

        fn initialize() *const e.ErlNifEntry {
            const nifs = spec.nifs_provider();
            entry = .{
                .major = 2,
                .minor = 16,
                .name = spec.name,
                .num_of_funcs = @intCast(nifs.len),
                .funcs = if (nifs.len == 0) null else nifs.ptr,
                .load = spec.load,
                .reload = null,
                .upgrade = upgrade,
                .unload = unload,
                .vm_variant = "beam.vanilla",
                .options = 1,
                .sizeof_ErlNifResourceTypeInit = @sizeOf(e.ErlNifResourceTypeInit),
                .min_erts = min_erts,
            };
            return &entry;
        }

        const windows_callbacks_target = if (@hasField(Spec, "windows_callbacks_target"))
            spec.windows_callbacks_target
        else
            null;
        const NifInit = EntryPoint(initialize, windows_callbacks_target);

        comptime {
            NifInit.exportSymbols();
        }
    };
}

pub const numOfNIFsPerKind = 10;

/// Adapts a typed resource cleanup function to the C ABI callback expected by
/// ERTS. Keeping the cast here lets resource implementations expose their
/// destructor as `pub const destroy = resourceDestructor(T, T.close)` while
/// their cleanup policy and locking remain private and backend-specific.
pub fn resourceDestructor(comptime ElementType: type, comptime close: anytype) e.ErlNifResourceDtor {
    const Expected = fn (*ElementType) void;
    if (@TypeOf(close) != Expected) {
        @compileError("resourceDestructor close must be fn(*" ++ @typeName(ElementType) ++ ") void, got " ++ @typeName(@TypeOf(close)));
    }

    return struct {
        fn call(_: beam.env, object: ?*anyopaque) callconv(.c) void {
            close(@ptrCast(@alignCast(object orelse return)));
        }
    }.call;
}

/// Owns one ERTS resource-type handle without generating the pointer, array,
/// or NIF surface provided by `ResourceKind`. Allocation, lookup, and reference
/// management are mechanical; initialization and destruction policy remain
/// with the caller.
pub fn RawResourceType(comptime ElementType: type, comptime name: anytype, comptime dtor: anytype) type {
    if (@TypeOf(dtor) != e.ErlNifResourceDtor) {
        @compileError("RawResourceType destructor must be ErlNifResourceDtor, got " ++ @typeName(@TypeOf(dtor)));
    }

    return struct {
        pub const Error = error{FailedToAllocateResource};
        pub const resource_name = name;
        pub var resource_type: beam.resource_type = undefined;

        pub fn open(environment: beam.env) void {
            resource_type = nifApi("enif_open_resource_type")(
                environment,
                null,
                resource_name,
                dtor,
                e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER,
                null,
            );
            if (resource_type == null) @panic("failed to open raw resource type");
        }

        /// Returns a caller-owned native resource reference.
        pub fn alloc() Error!*ElementType {
            const memory = nifApi("enif_alloc_resource")(resource_type, @sizeOf(ElementType)) orelse
                return Error.FailedToAllocateResource;
            return @ptrCast(@alignCast(memory));
        }

        pub fn fetch(environment: beam.env, term: beam.term) !*ElementType {
            return beam.fetch_resource_ptr(*ElementType, environment, resource_type, term);
        }

        /// Copies `value` into a new resource and transfers its native
        /// allocation reference to the returned BEAM term.
        pub fn make(environment: beam.env, value: ElementType) !beam.term {
            return beam.make_resource(environment, value, resource_type);
        }

        pub fn keep(resource: *ElementType) void {
            nifApi("enif_keep_resource")(resource);
        }

        pub fn release(resource: *ElementType) void {
            nifApi("enif_release_resource")(resource);
        }
    };
}

pub fn ResourceKind(comptime ElementType: type, comptime module_name_: anytype) type {
    return struct {
        pub const module_name = module_name_;
        pub const T = ElementType;
        const PtrType = if (@typeInfo(ElementType) == .@"struct" and @hasDecl(ElementType, "PtrType"))
            ElementType.PtrType
        else
            [*c]ElementType; // translate-c pointer type
        pub const resource = struct {
            pub var t: beam.resource_type = undefined;
            pub const name = @typeName(ElementType);
            pub fn make(env: beam.env, value: T) !beam.term {
                return beam.make_resource(env, value, t);
            }
            pub fn make_kind(env: beam.env, value: T) !beam.term {
                var tuple_slice: []beam.term = beam.allocator.alloc(beam.term, 3) catch return beam.Error.@"Fail to allocate memory for tuple slice";
                defer beam.allocator.free(tuple_slice);
                tuple_slice[0] = beam.make_atom(env, "kind");
                tuple_slice[1] = beam.make_atom(env, module_name);
                const ret = resource.make(env, value) catch return beam.Error.@"Fail to make resource for return type";
                tuple_slice[2] = ret;
                return beam.make_tuple(env, tuple_slice);
            }
            pub fn fetch(env: beam.env, arg: beam.term) !T {
                return beam.fetch_resource(T, env, t, arg);
            }
            pub fn fetch_ptr(env: beam.env, arg: beam.term) !PtrType {
                return beam.fetch_resource_ptr(PtrType, env, t, arg);
            }
        };
        pub const Ptr = struct {
            pub const module_name = module_name_ ++ ".Ptr";
            pub const T = PtrType;
            pub const resource = struct {
                pub var t: beam.resource_type = undefined;
                pub const name = @typeName(PtrType);
                pub fn make(env: beam.env, value: PtrType) !beam.term {
                    return beam.make_resource(env, value, t);
                }
                pub fn fetch(env: beam.env, arg: beam.term) !PtrType {
                    return beam.fetch_resource(PtrType, env, t, arg);
                }
            };
        };
        const ArrayType = if (@typeInfo(ElementType) == .@"struct" and @hasDecl(ElementType, "ArrayType"))
            ElementType.ArrayType
        else
            [*c]const ElementType; // translate-c Array type
        pub const Array = struct {
            pub const module_name = module_name_ ++ ".Array";
            pub const T = ArrayType;
            pub const resource = struct {
                pub var t: beam.resource_type = undefined;
                pub const name = @typeName(ArrayType);
                pub fn make(env: beam.env, value: ArrayType) !beam.term {
                    return beam.make_resource(env, value, t);
                }
                pub fn fetch(env: beam.env, arg: beam.term) !ArrayType {
                    return beam.fetch_resource(ArrayType, env, t, arg);
                }
            };
            // get the array adress as a opaque array
            pub fn as_opaque(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
                const array_ptr: ArrayType = @This().resource.fetch(env, args[0]) catch
                    return beam.Error.@"Fail to fetch resource for array";
                return Internal.OpaqueArray.resource.make(env, @ptrCast(array_ptr)) catch
                    return beam.Error.@"Fail to make resource for opaque array";
            }
        };
        fn ptr(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            return beam.get_resource_ptr_from_term(env, @This().PtrType, @This().resource.t, Ptr.resource.t, args[0]) catch return beam.Error.@"Fail to make ptr resource";
        }
        fn ptr_to_opaque(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const typed_ptr: Ptr.T = Ptr.resource.fetch(env, args[0]) catch return beam.Error.@"Fail to fetch ptr resource";
            return Internal.OpaquePtr.resource.make(env, @ptrCast(typed_ptr)) catch return beam.Error.@"Fail to make resource for opaque ptr";
        }
        pub fn opaque_ptr(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const ptr_to_resource_memory: Ptr.T = beam.fetch_resource_ptr(@This().PtrType, env, @This().resource.t, args[0]) catch return beam.Error.@"Fail to fetch ptr resource";
            return Internal.OpaquePtr.resource.make(env, @ptrCast(ptr_to_resource_memory)) catch return beam.Error.@"Fail to make resource for opaque ptr";
        }
        // the returned term owns the memory of the array.
        fn array(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            return beam.get_resource_array(T, env, @This().resource.t, Array.resource.t, args[0]) catch return beam.Error.@"Fail to make array resource";
        }
        // the returned term owns the memory of the array.
        // TODO: mut array should be a dedicated resource type without reusing Ptr.resource.t
        fn mut_array(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            return beam.get_resource_array(T, env, @This().resource.t, Ptr.resource.t, args[0]) catch beam.Error.@"Fail to make mutable array resource";
        }
        fn primitive(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const v = resource.fetch(env, args[0]) catch return beam.Error.@"Fail to fetch primitive";
            return beam.make(T, env, v) catch return beam.Error.@"Fail to create primitive";
        }
        fn dump(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const v: T = resource.fetch(env, args[0]) catch return beam.Error.@"Fail to fetch primitive";
            const format_string = switch (@typeInfo(T)) {
                .pointer => "{*}\n",
                else => "{any}\n",
            };
            const rendered = try std.fmt.allocPrint(std.heap.page_allocator, format_string, .{v});
            defer std.heap.page_allocator.free(rendered);
            return beam.make_slice(env, rendered);
        }
        fn append_to_struct(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const v = resource.fetch(env, args[0]) catch return beam.Error.@"Fail to fetch primitive";
            return beam.make(T, env, v) catch return beam.Error.@"Fail to create primitive";
        }
        fn make(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const v = beam.get(T, env, args[0]) catch return beam.Error.@"Fail to fetch primitive";
            return resource.make(env, v) catch return beam.Error.@"Fail to create primitive";
        }
        const OpaquePtrError = error{ @"Fail to fetch resource opaque ptr", failToFetchOffset, @"Fail to allocate memory for tuple slice", @"Fail to make resource for extracted object", @"Fail to make object size" };
        fn make_from_opaque_ptr(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const ptr_to_read: Internal.OpaquePtr.T = Internal.OpaquePtr.resource.fetch(env, args[0]) catch
                return beam.Error.@"Fail to fetch resource opaque ptr";
            const offset: Internal.USize.T = Internal.USize.resource.fetch(env, args[1]) catch
                return beam.Error.@"Fail to fetch offset";
            const ptr_int = @intFromPtr(ptr_to_read) + offset;
            const obj_ptr: *ElementType = @ptrFromInt(ptr_int);
            var tuple_slice: []beam.term = beam.allocator.alloc(beam.term, 2) catch return beam.Error.@"Fail to allocate memory for tuple slice";
            defer beam.allocator.free(tuple_slice);
            tuple_slice[0] = resource.make(env, obj_ptr.*) catch return beam.Error.@"Fail to make resource for extracted object";
            tuple_slice[1] = beam.make(Internal.USize.T, env, @sizeOf(ElementType)) catch return beam.Error.@"Fail to make object size";
            return beam.make_tuple(env, tuple_slice);
        }
        const maker = if (@typeInfo(ElementType) == .@"struct" and @hasDecl(ElementType, "maker"))
            ElementType.maker
        else
            .{ make, 1 };
        const ptr_maker = if (@typeInfo(ElementType) == .@"struct" and @hasDecl(ElementType, "ptr"))
            ElementType.ptr
        else
            ptr;
        const extra_nifs = if (@typeInfo(ElementType) == .@"struct" and @hasDecl(ElementType, "nifs"))
            ElementType.nifs
        else
            .{};
        pub const nifs: [numOfNIFsPerKind + @typeInfo(@TypeOf(extra_nifs)).@"struct".fields.len]e.ErlNifFunc = .{
            result.nif(module_name ++ ".ptr", 1, ptr_maker).entry,
            result.nif(module_name ++ ".ptr_to_opaque", 1, ptr_to_opaque).entry,
            result.nif(module_name ++ ".opaque_ptr", 1, opaque_ptr).entry,
            result.nif(module_name ++ ".array", 1, array).entry,
            result.nif(module_name ++ ".mut_array", 1, mut_array).entry,
            result.nif(module_name ++ ".primitive", 1, primitive).entry,
            result.nif(module_name ++ ".make", maker[1], maker[0]).entry,
            result.nif(module_name ++ ".dump", 1, dump).entry,
            result.nif(module_name ++ ".make_from_opaque_ptr", 2, make_from_opaque_ptr).entry,
            result.nif(module_name ++ ".array_as_opaque", 1, @This().Array.as_opaque).entry,
        } ++ extra_nifs;
        const primary_dtor = if (@typeInfo(ElementType) == .@"struct" and @hasDecl(ElementType, "destroy"))
            ElementType.destroy
        else
            beam.destroy_do_nothing;

        /// The three resource slots owned by this kind, in a stable order:
        /// the value slot first, then its `Ptr` and `Array` wrappers. Used by
        /// `open_all` and by downstream registries that need one handle per
        /// slot name.
        pub const slots = [_]ResourceSlot{
            .{ .name = resource.name, .t = &resource.t, .dtor = primary_dtor },
            .{ .name = Ptr.resource.name, .t = &Ptr.resource.t, .dtor = beam.destroy_do_nothing },
            .{ .name = Array.resource.name, .t = &Array.resource.t, .dtor = beam.destroy_do_nothing },
        };

        fn openSlot(env: beam.env, slot: ResourceSlot) void {
            slot.t.* = nifApi("enif_open_resource_type")(env, null, slot.name.ptr, slot.dtor, e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER, null);
        }

        pub fn open(env: beam.env) void {
            openSlot(env, slots[0]);
            if (@typeInfo(ElementType) == .@"struct" and @hasDecl(ElementType, "resource_type")) {
                ElementType.resource_type = @This().resource.t;
            }
        }
        pub fn open_ptr(env: beam.env) void {
            openSlot(env, slots[1]);
        }
        pub fn open_array(env: beam.env) void {
            // TODO: use a ArrayList/BoundedArray to store the array and deinit it in destroy callback
            openSlot(env, slots[2]);
        }
        pub fn open_all(env: beam.env) void {
            inline for (slots) |slot| {
                openSlot(env, slot);
            }
            if (@typeInfo(ElementType) == .@"struct" and @hasDecl(ElementType, "resource_type")) {
                ElementType.resource_type = @This().resource.t;
            }
        }
    };
}

pub fn ResourceKind2(comptime ElementType: type) type {
    return ResourceKind(ElementType, ElementType.module_name);
}

pub fn aliasKind(comptime AliasKind: type, comptime Kind: type) void {
    // Copy every slot handle: the two kinds share one ERTS resource type per
    // slot so terms created through either name fetch the same native data.
    inline for (AliasKind.slots, Kind.slots) |alias_slot, target_slot| {
        alias_slot.t.* = target_slot.t.*;
    }
}

pub fn open_internal_resource_types(env: beam.env) void {
    Internal.USize.open_all(env);
    Internal.OpaquePtr.open_all(env);
    Internal.OpaqueArray.open_all(env);
}

const NIFFuncAttrs = struct { flags: u32 = 0, nif_name: ?[*c]const u8 = null };

// Preserve the original source API for downstream handwritten wrappers.
pub fn BangFunc(
    comptime Kinds: anytype,
    c: anytype,
    comptime name: []const u8,
) type {
    return BangFuncWithNIFName(Kinds, c, name, @ptrCast(name.ptr));
}

// Wrap a C function while reporting the exported NIF name in diagnostics.
pub fn BangFuncWithNIFName(
    comptime Kinds: anytype,
    c: anytype,
    comptime name: anytype,
    comptime nif_name: [*c]const u8,
) type {
    @setEvalBranchQuota(5000);
    const cfunction = @field(c, name);
    const FTI = @typeInfo(@TypeOf(cfunction)).@"fn";
    return (struct {
        pub const arity = FTI.params.len;
        fn getKind(comptime t: type) type {
            for (Kinds) |kind| {
                switch (@typeInfo(t)) {
                    .pointer => {
                        if (t == kind.Ptr.T) {
                            return kind.Ptr;
                        }
                        if (t == kind.Array.T) {
                            return kind.Array;
                        }
                        if (t == kind.T) {
                            return kind;
                        }
                    },
                    else => {
                        if (t == kind.T) {
                            return kind;
                        }
                    },
                }
            }
            @compileError("resouce kind not found " ++ @typeName(t));
        }
        inline fn VariadicArgs() type {
            var types: [FTI.params.len]type = undefined;
            inline for (FTI.params, 0..) |param, i| {
                types[i] = param.type orelse @compileError("anytype C arguments are unsupported");
            }
            return @Tuple(&types);
        }
        inline fn variadic_call(args: VariadicArgs()) FTI.return_type.? {
            return @call(.auto, cfunction, args);
        }
        pub fn wrap_ret_call(env: beam.env, args: anytype) !beam.term {
            const rt = FTI.return_type.?;
            const RetKind = getKind(rt);
            var tuple_slice: []beam.term = beam.allocator.alloc(beam.term, 3) catch |err| return beam.raise_call_error(env, .{
                .message = "Fail to allocate memory for tuple slice",
                .reason = "return_encode_failed",
                .phase = "return_encode",
                .function = std.mem.span(nif_name),
                .arity = arity,
                .native_error = err,
            });
            defer beam.allocator.free(tuple_slice);
            tuple_slice[0] = beam.make_atom(env, "kind");
            tuple_slice[1] = beam.make_atom(env, RetKind.module_name);
            const ret = RetKind.resource.make(env, @call(.auto, variadic_call, .{args})) catch |err| return beam.raise_call_error(env, .{
                .message = "Fail to make resource for return type",
                .reason = "return_encode_failed",
                .phase = "return_encode",
                .function = std.mem.span(nif_name),
                .arity = arity,
                .expected = RetKind.resource.name,
                .native_error = err,
            });
            tuple_slice[2] = ret;
            return beam.make_tuple(env, tuple_slice);
        }
        pub fn nif(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            @setEvalBranchQuota(100_000);
            var c_args: VariadicArgs() = undefined;
            inline for (FTI.params, args, 0..) |p, arg, i| {
                const ArgKind = getKind(p.type.?);
                c_args[i] = ArgKind.resource.fetch(env, arg) catch |err| return beam.raise_call_error(env, .{
                    .message = "Fail to fetch argument #" ++ std.fmt.comptimePrint("{d}", .{i + 1}),
                    .reason = "argument_decode_failed",
                    .phase = "argument_decode",
                    .function = std.mem.span(nif_name),
                    .arity = arity,
                    .argument_index = i + 1,
                    .expected = ArgKind.resource.name,
                    .native_error = err,
                });
            }
            const rt = FTI.return_type.?;
            if (rt == void) {
                variadic_call(c_args);
                return beam.make_ok(env);
            } else {
                return wrap_ret_call(env, c_args);
            }
        }
    });
}

pub fn NIFFunc(comptime Kinds: anytype, c: anytype, comptime name: anytype, comptime attrs: NIFFuncAttrs) e.ErlNifFunc {
    const nif_name = attrs.nif_name orelse name;
    const bang = BangFuncWithNIFName(Kinds, c, name, nif_name);
    return result.nif_with_flags(nif_name, bang.arity, bang.nif, attrs.flags).entry;
}
