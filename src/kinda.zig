const beam = @import("beam");
const e = @import("erl_nif");
const std = @import("std");
pub const result = @import("result.zig");

// a function to make a resource term from a u8 slice.
const OpaqueMaker: type = fn (beam.env, []u8) beam.term;
pub const OpaqueStructType = struct {
    const Accessor: type = struct { maker: OpaqueMaker, offset: usize };
    const ArrayType = ?*anyopaque;
    const PtrType = ?*anyopaque;
    storage: std.ArrayList(u8) = std.ArrayList(u8).init(beam.allocator),
    finalized: bool, // if it is finalized, can't append more fields to it. Only finalized struct can be addressed.
    accessors: std.ArrayList(Accessor),
};

pub const OpaqueField = extern struct {
    storage: std.ArrayList(u8),
    maker: type = OpaqueMaker,
};

pub const Internal = struct {
    pub const OpaquePtr: type = ResourceKind(?*anyopaque, "Kinda.Internal.OpaquePtr");
    pub const OpaqueArray: type = ResourceKind(?*const anyopaque, "Kinda.Internal.OpaqueArray");
    pub const USize: type = ResourceKind(usize, "Kinda.Internal.USize");
    pub const OpaqueStruct: type = ResourceKind(OpaqueStructType, "Kinda.Internal.OpaqueStruct");
};

pub const numOfNIFsPerKind = 10;
pub fn ResourceKind(comptime ElementType: type, comptime module_name_: anytype) type {
    return struct {
        pub const module_name = module_name_;
        pub const T = ElementType;
        pub const resource = struct {
            pub var t: beam.resource_type = undefined;
            pub const name = @typeName(ElementType);
            pub fn make(env: beam.env, value: T) !beam.term {
                return beam.make_resource(env, value, t);
            }
            pub fn fetch(env: beam.env, arg: beam.term) !T {
                return beam.fetch_resource(T, env, t, arg);
            }
            pub fn fetch_ptr(env: beam.env, arg: beam.term) !*T {
                return beam.fetch_resource_ptr(T, env, t, arg);
            }
        };
        const PtrType = if (@typeInfo(ElementType) == .Struct and @hasDecl(ElementType, "PtrType"))
            ElementType.PtrType
        else
            [*c]ElementType;
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
        const ArrayType = if (@typeInfo(ElementType) == .Struct and @hasDecl(ElementType, "ArrayType"))
            ElementType.ArrayType
        else
            [*c]const ElementType;
        pub const Array = struct {
            pub const module_name = module_name_ ++ ".Array";
            pub const T = ArrayType;
            const Error = error{ failToFetchResourceForArray, failToMakeResourceForOpaqueArray };
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
                    return Error.failToFetchResourceForArray;
                return Internal.OpaqueArray.resource.make(env, @ptrCast(array_ptr)) catch
                    return Error.failToMakeResourceForOpaqueArray;
            }
        };
        const PtrError = error{ failToMakePtrResource, failToFetchPtrResource, failToMakeResourceForOpaquePtr, failToMakeArrayResource, failToMakeMutableArrayResource };
        fn ptr(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            return beam.get_resource_ptr_from_term(T, env, @This().resource.t, Ptr.resource.t, args[0]) catch return PtrError.failToMakePtrResource;
        }
        fn ptr_to_opaque(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const typed_ptr: Ptr.T = Ptr.resource.fetch(env, args[0]) catch return PtrError.failToFetchPtrResource;
            return Internal.OpaquePtr.resource.make(env, @ptrCast(typed_ptr)) catch return PtrError.failToMakeResourceForOpaquePtr;
        }
        pub fn opaque_ptr(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const ptr_to_resource_memory: Ptr.T = beam.fetch_resource_ptr(T, env, @This().resource.t, args[0]) catch return PtrError.failToFetchPtrResource;
            return Internal.OpaquePtr.resource.make(env, @ptrCast(ptr_to_resource_memory)) catch return PtrError.failToMakeResourceForOpaquePtr;
        }
        // the returned term owns the memory of the array.
        fn array(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            return beam.get_resource_array(T, env, @This().resource.t, Array.resource.t, args[0]) catch return PtrError.failToMakeArrayResource;
        }
        // the returned term owns the memory of the array.
        // TODO: mut array should be a dedicated resource type without reusing Ptr.resource.t
        fn mut_array(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            return beam.get_resource_array(T, env, @This().resource.t, Ptr.resource.t, args[0]) catch PtrError.failToMakeMutableArrayResource;
        }
        const PrimitiveError = error{ failToFetchPrimitive, failToCreatePrimitive };
        fn primitive(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const v = resource.fetch(env, args[0]) catch return PrimitiveError.failToFetchPrimitive;
            return beam.make(T, env, v) catch return PrimitiveError.failToCreatePrimitive;
        }
        fn dump(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const v: T = resource.fetch(env, args[0]) catch return PrimitiveError.failToFetchPrimitive;
            var buffer = try std.ArrayList(u8).initCapacity(std.heap.page_allocator, 100);
            defer buffer.deinit();
            const format_string = switch (@typeInfo(T)) {
                .Pointer => "{*}\n",
                else => "{?}\n",
            };
            try std.fmt.format(buffer.writer(), format_string, .{v});
            return beam.make_slice(env, buffer.items);
        }
        fn append_to_struct(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const v = resource.fetch(env, args[0]) catch return PrimitiveError.failToFetchPrimitive;
            return beam.make(T, env, v) catch return PrimitiveError.failToCreatePrimitive;
        }
        fn make(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const v = beam.get(T, env, args[0]) catch return PrimitiveError.failToFetchPrimitive;
            return resource.make(env, v) catch return PrimitiveError.failToCreatePrimitive;
        }
        const OpaquePtrError = error{ failToFetchResourceOpaquePtr, failToFetchOffset, failToAllocateMemoryForTupleSlice, failToMakeResourceForExtractedObject, failToMakeObjectSize };
        fn make_from_opaque_ptr(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const ptr_to_read: Internal.OpaquePtr.T = Internal.OpaquePtr.resource.fetch(env, args[0]) catch
                return OpaquePtrError.failToFetchResourceOpaquePtr;
            const offset: Internal.USize.T = Internal.USize.resource.fetch(env, args[1]) catch
                return OpaquePtrError.failToFetchOffset;
            const ptr_int = @intFromPtr(ptr_to_read) + offset;
            const obj_ptr: *ElementType = @ptrFromInt(ptr_int);
            var tuple_slice: []beam.term = beam.allocator.alloc(beam.term, 2) catch return OpaquePtrError.failToAllocateMemoryForTupleSlice;
            defer beam.allocator.free(tuple_slice);
            tuple_slice[0] = resource.make(env, obj_ptr.*) catch return OpaquePtrError.failToMakeResourceForExtractedObject;
            tuple_slice[1] = beam.make(Internal.USize.T, env, @sizeOf(ElementType)) catch return OpaquePtrError.failToMakeObjectSize;
            return beam.make_tuple(env, tuple_slice);
        }
        const maker = if (@typeInfo(ElementType) == .Struct and @hasDecl(ElementType, "maker"))
            ElementType.maker
        else
            .{ make, 1 };
        const ptr_maker = if (@typeInfo(ElementType) == .Struct and @hasDecl(ElementType, "ptr"))
            ElementType.ptr
        else
            ptr;
        const extra_nifs = if (@typeInfo(ElementType) == .Struct and @hasDecl(ElementType, "nifs"))
            ElementType.nifs
        else
            .{};
        pub const nifs: [numOfNIFsPerKind + @typeInfo(@TypeOf(extra_nifs)).Struct.fields.len]e.ErlNifFunc = .{
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
        pub fn open(env: beam.env) void {
            const dtor = if (@typeInfo(ElementType) == .Struct and @hasDecl(ElementType, "destroy"))
                ElementType.destroy
            else
                beam.destroy_do_nothing;
            @This().resource.t = e.enif_open_resource_type(env, null, @This().resource.name, dtor, e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER, null);
            if (@typeInfo(ElementType) == .Struct and @hasDecl(ElementType, "resource_type")) {
                ElementType.resource_type = @This().resource.t;
            }
        }
        pub fn open_ptr(env: beam.env) void {
            @This().Ptr.resource.t = e.enif_open_resource_type(env, null, @This().Ptr.resource.name, beam.destroy_do_nothing, e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER, null);
        }
        pub fn open_array(env: beam.env) void {
            // TODO: use a ArrayList/BoundedArray to store the array and deinit it in destroy callback
            @This().Array.resource.t = e.enif_open_resource_type(env, null, @This().Array.resource.name, beam.destroy_do_nothing, e.ERL_NIF_RT_CREATE | e.ERL_NIF_RT_TAKEOVER, null);
        }
        pub fn open_all(env: beam.env) void {
            open(env);
            open_ptr(env);
            open_array(env);
        }
    };
}

pub fn ResourceKind2(comptime ElementType: type) type {
    return ResourceKind(ElementType, ElementType.module_name);
}

pub fn aliasKind(comptime AliasKind: type, comptime Kind: type) void {
    AliasKind.resource.t = Kind.resource.t;
    AliasKind.Ptr.resource.t = Kind.Ptr.resource.t;
    AliasKind.Array.resource.t = Kind.Array.resource.t;
}

pub fn open_internal_resource_types(env: beam.env) void {
    Internal.USize.open_all(env);
    Internal.OpaquePtr.open_all(env);
    Internal.OpaqueArray.open_all(env);
}

const NIFFuncAttrs = struct { flags: u32 = 0, nif_name: ?[*c]const u8 = null };
pub fn NIFFunc(comptime Kinds: anytype, c: anytype, comptime name: anytype, attrs: NIFFuncAttrs) e.ErlNifFunc {
    @setEvalBranchQuota(5000);
    const cfunction = @field(c, name);
    const FTI = @typeInfo(@TypeOf(cfunction)).Fn;
    const flags = attrs.flags;
    return (struct {
        fn getKind(comptime t: type) type {
            for (Kinds) |kind| {
                switch (@typeInfo(t)) {
                    .Pointer => {
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
            const P = FTI.params;
            return switch (P.len) {
                0 => struct {},
                1 => struct { P[0].type.? },
                2 => struct { P[0].type.?, P[1].type.? },
                3 => struct { P[0].type.?, P[1].type.?, P[2].type.? },
                4 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.? },
                5 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.? },
                6 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.? },
                7 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.? },
                8 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.? },
                9 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.? },
                10 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.?, P[9].type.? },
                11 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.?, P[9].type.?, P[10].type.? },
                12 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.?, P[9].type.?, P[10].type.?, P[11].type.? },
                13 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.?, P[9].type.?, P[10].type.?, P[11].type.?, P[12].type.? },
                14 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.?, P[9].type.?, P[10].type.?, P[11].type.?, P[12].type.?, P[13].type.? },
                15 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.?, P[9].type.?, P[10].type.?, P[11].type.?, P[12].type.?, P[13].type.?, P[14].type.? },
                16 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.?, P[9].type.?, P[10].type.?, P[11].type.?, P[12].type.?, P[13].type.?, P[14].type.?, P[15].type.? },
                17 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.?, P[9].type.?, P[10].type.?, P[11].type.?, P[12].type.?, P[13].type.?, P[14].type.?, P[15].type.?, P[16].type.? },
                18 => struct { P[0].type.?, P[1].type.?, P[2].type.?, P[3].type.?, P[4].type.?, P[5].type.?, P[6].type.?, P[7].type.?, P[8].type.?, P[9].type.?, P[10].type.?, P[11].type.?, P[12].type.?, P[13].type.?, P[14].type.?, P[15].type.?, P[16].type.?, P[17].type.? },
                else => @compileError("too many args"),
            };
        }
        inline fn variadic_call(args: anytype) FTI.return_type.? {
            const f = cfunction;
            return switch (FTI.params.len) {
                0 => f(),
                1 => f(args[0]),
                2 => f(args[0], args[1]),
                3 => f(args[0], args[1], args[2]),
                4 => f(args[0], args[1], args[2], args[3]),
                5 => f(args[0], args[1], args[2], args[3], args[4]),
                6 => f(args[0], args[1], args[2], args[3], args[4], args[5]),
                7 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6]),
                8 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]),
                9 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8]),
                10 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9]),
                11 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10]),
                12 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11]),
                13 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12]),
                14 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13]),
                15 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13], args[14]),
                16 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13], args[14], args[15]),
                17 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13], args[14], args[15], args[16]),
                18 => f(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13], args[14], args[15], args[16], args[17]),
                else => @compileError("too many args"),
            };
        }
        fn nif(env: beam.env, _: c_int, args: [*c]const beam.term) !beam.term {
            const Error = error{ failToMakeResourceForReturnType, failToAllocateMemoryForTupleSlice, failToFetchArgumentResource };
            var c_args: VariadicArgs() = undefined;
            inline for (FTI.params, args, 0..) |p, arg, i| {
                const ArgKind = getKind(p.type.?);
                c_args[i] = ArgKind.resource.fetch(env, arg) catch return Error.failToFetchArgumentResource;
            }
            const rt = FTI.return_type.?;
            if (rt == void) {
                variadic_call(c_args);
                return beam.make_ok(env);
            } else {
                const RetKind = getKind(rt);
                var tuple_slice: []beam.term = beam.allocator.alloc(beam.term, 3) catch return Error.failToAllocateMemoryForTupleSlice;
                defer beam.allocator.free(tuple_slice);
                tuple_slice[0] = beam.make_atom(env, "kind");
                tuple_slice[1] = beam.make_atom(env, RetKind.module_name);
                const ret = RetKind.resource.make(env, variadic_call(c_args)) catch return Error.failToMakeResourceForReturnType;
                tuple_slice[2] = ret;
                return beam.make_tuple(env, tuple_slice);
            }
        }
        const entry = result.nif_with_flags(attrs.nif_name orelse name, FTI.params.len, nif, flags).entry;
    }).entry;
}
