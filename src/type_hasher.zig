// zlint-disable case-convention
const std = @import("std");
const TypeIdInt = @import("types.zig").TypeIdInt;

fn checkForNameCollision(comptime Types: []const type) void {
    inline for (Types, 0..) |T, i| {
        inline for (Types[i + 1 ..]) |U| {
            if (std.mem.eql(u8, @typeName(T), @typeName(U))) {
                @compileError("Type name collision detected between '" ++
                    @typeName(T) ++
                    "' and '" ++
                    @typeName(U) ++
                    "'. Mind changing one of the types name?" ++
                    "@typeName is the only way to generate unique hashes at comptime." ++
                    "For further explanations: https://ziggit.dev/t/type-id-comptime-generation/10956/8");
            }
        }
    }
}

fn initTypeId(comptime Types: []const type) type {
    checkForNameCollision(Types);
    var field_names: [Types.len][]const u8 = undefined;
    var field_attributes: [Types.len]TypeIdInt = undefined;
    for (Types, 0..) |Type, i| {
        field_names[i] = @typeName(Type);
        field_attributes[i] = i;
    }
    return @Enum(
        TypeIdInt,
        .exhaustive,
        &field_names,
        &field_attributes,
    );
}

pub fn TypeHasher(comptime Types: []const type) type {
    return struct {
        // throw error for repeated types
        // this should force everybody to use wrappers around their components
        comptime {
            for (Types, 0..) |Type, i| {
                if (std.mem.indexOfScalar(type, Types[0..i], Type) != null) {
                    @compileError("type '" ++ @typeName(Type) ++ "' was already registered");
                }
            }
        }

        /// enum that will be used to make typeIds (tid) typed
        /// EVERY tid should be TypeId
        pub const TypeId = initTypeId(Types);
        pub const Len = Types.len;
        pub const MaxAlignment = if (Types.len > 0) std.mem.max(usize, TypeIdAlignmentMap.values[0..]) else 1;

        pub const Union = Union: {
            var field_names: [Len][]const u8 = undefined;
            var field_types: [Len]type = undefined;
            var field_attributes: [Len]std.builtin.Type.UnionField.Attributes = undefined;
            for (Types, 0..) |Type, i| {
                field_names[i] = @typeName(Type);
                field_types[i] = Type;
                field_attributes[i] = std.builtin.Type.UnionField.Attributes{
                    .@"align" = @alignOf(Type),
                };
            }
            break :Union @Union(
                .auto,
                TypeId,
                &field_names,
                &field_types,
                &field_attributes,
            );
        };

        /// for functions receiving a tid, use a static enum map to return info in O(1)
        const TypeIdSizeMap = TypeIdSizeMap: {
            @setEvalBranchQuota(Types.len * Types.len * Types.len * 100);
            var map = std.EnumArray(TypeId, usize).initUndefined();
            for (Types) |Type| {
                const type_id = std.meta.stringToEnum(TypeId, @typeName(Type)).?;
                map.set(type_id, @sizeOf(Type));
            }
            break :TypeIdSizeMap map;
        };
        const TypeIdAlignmentMap = TypeIdAlignmentMap: {
            @setEvalBranchQuota(Types.len * Types.len * Types.len * 100);
            var map = std.EnumArray(TypeId, usize).initUndefined();
            for (Types) |Type| {
                const type_id = std.meta.stringToEnum(TypeId, @typeName(Type)).?;
                map.set(type_id, @alignOf(Type));
            }
            break :TypeIdAlignmentMap map;
        };
        /// for functions receiving a tid, use a static enum map to return info in O(1)
        const TypeIdIndexMap = TypeIdIndexMap: {
            @setEvalBranchQuota(Types.len * Types.len * Types.len * 100);
            var map = std.EnumArray(TypeId, usize).initUndefined();
            for (Types, 0..) |Type, i| {
                const type_id = std.meta.stringToEnum(TypeId, @typeName(Type)).?;
                map.set(type_id, i);
            }
            break :TypeIdIndexMap map;
        };
        const TypeIdNameMap = TypeIdNameMap: {
            @setEvalBranchQuota(Types.len * Types.len * Types.len * 100);
            var map = std.EnumArray(TypeId, [:0]const u8).initUndefined();
            for (Types) |Type| {
                const type_id = std.meta.stringToEnum(TypeId, @typeName(Type)).?;
                map.set(type_id, @typeName(Type));
            }
            break :TypeIdNameMap map;
        };

        pub const TypeIds = TypeIds: {
            @setEvalBranchQuota(Types.len * Types.len * Types.len * 100);
            var type_ids: [Types.len]TypeId = undefined;
            for (Types, 0..) |Type, i| {
                type_ids[i] = hash(Type);
            }
            break :TypeIds type_ids;
        };
        pub const Sizes = Sizes: {
            var sizes: [Types.len]usize = undefined;
            for (Types, 0..) |Type, i| {
                sizes[i] = @sizeOf(Type);
            }
            break :Sizes sizes;
        };

        pub fn extend(comptime T: type) type {
            var types: []const type = &.{T};
            types = types ++ Types;
            return TypeHasher(types);
        }

        pub fn isRegisteredType(comptime T: type) bool {
            return comptime std.mem.indexOfScalar(type, Types, T) != null;
        }

        pub fn getAsUnion(value: anytype) Union {
            const Type = @TypeOf(value);
            checkType(Type);
            return @unionInit(Union, @typeName(Type), value);
        }

        pub fn hash(comptime Type: type) TypeId {
            @setEvalBranchQuota(Types.len * Types.len * 100);
            if (comptime std.meta.stringToEnum(TypeId, @typeName(Type))) |id| {
                return id;
            }
            @compileError("type '" ++ @typeName(Type) ++ "' is not registered");
        }

        const AccessType = enum {
            Const,
            PointerConst,
            PointerMut,
            OptionalConst,
            OptionalPointerMut,
            OptionalPointerConst,
        };
        pub fn getAccessType(comptime T: type) AccessType {
            if (isRegisteredType(T)) return .Const;
            return switch (@typeInfo(T)) {
                .pointer => |p| {
                    if (!isRegisteredType(p.child)) {
                        @compileError("Pointer doesn't point to a registered type");
                    }
                    return if (p.is_const) .PointerConst else .PointerMut;
                },
                .optional => |o| switch (@typeInfo(o.child)) {
                    .pointer => |p| {
                        if (!isRegisteredType(p.child)) {
                            @compileError("Child of optional pointer (" ++ @typeName(T) ++ ") is not a registered type");
                        }
                        return if (p.is_const) .OptionalPointerConst else .OptionalPointerMut;
                    },
                    else => {
                        if (!isRegisteredType(o.child)) {
                            @compileError("Child of optional (" ++ @typeName(T) ++ ") is not a registered type");
                        }
                        return .OptionalConst;
                    },
                },
                else => {
                    @compileError("type is not a registered type");
                },
            };
        }

        pub fn getCanonicalType(comptime T: type) type {
            if (isRegisteredType(T)) return T;
            return switch (@typeInfo(T)) {
                .pointer => |p| {
                    if (!isRegisteredType(p.child)) {
                        @compileError("Pointer " ++ @typeName(T) ++ " doesn't point to a registered type");
                    }
                    return p.child;
                },
                .optional => |o| switch (@typeInfo(o.child)) {
                    .pointer => |p| {
                        if (!isRegisteredType(p.child)) {
                            @compileError("Child of optional pointer (" ++ @typeName(T) ++ ") is not a registered type");
                        }
                        return p.child;
                    },
                    else => {
                        if (!isRegisteredType(o.child)) {
                            @compileError("Child of optional (" ++ @typeName(T) ++ ") is not a registered type");
                        }
                        return o.child;
                    },
                },
                else => {
                    @compileError("type '" ++ @typeName(T) ++ "' is not a registered type");
                },
            };
        }

        pub inline fn checkType(tid_or_type: anytype) void {
            if (comptime @TypeOf(tid_or_type) != TypeId and !@This().isRegisteredType(tid_or_type)) {
                const T = T: {
                    if (comptime @TypeOf(tid_or_type) == type) {
                        break :T tid_or_type;
                    }
                    break :T @TypeOf(tid_or_type);
                };
                @compileError("invalid type " ++ @typeName(T) ++ ": must be a TypeId or a type in the registered list");
            }
        }

        pub inline fn getSize(tid_or_type: anytype) usize {
            if (comptime Len == 0) return 0;
            if (comptime @TypeOf(tid_or_type) == TypeId) {
                return TypeIdSizeMap.get(tid_or_type);
            } else if (comptime isRegisteredType(tid_or_type)) {
                return @sizeOf(tid_or_type);
            }
            @compileError("invalid type " ++
                @typeName(@TypeOf(tid_or_type)) ++
                ": must be a TypeId or a type in the registered list");
        }

        pub inline fn getAlignment(tid_or_type: anytype) usize {
            if (comptime Len == 0) return 0;
            if (comptime @TypeOf(tid_or_type) == TypeId) {
                return TypeIdAlignmentMap.get(tid_or_type);
            } else if (comptime isRegisteredType(tid_or_type)) {
                return @alignOf(tid_or_type);
            }
            @compileError("invalid type " ++
                @typeName(@TypeOf(tid_or_type)) ++
                ": must be a TypeId or a type in the registered list");
        }

        pub inline fn getIndex(tid_or_type: anytype) usize {
            if (comptime Len == 0) return 0;
            if (comptime @TypeOf(tid_or_type) == TypeId) {
                return TypeIdIndexMap.get(tid_or_type);
            } else if (comptime isRegisteredType(tid_or_type)) {
                if (comptime std.mem.indexOfScalar(type, Types, tid_or_type)) |idx| {
                    return idx;
                }
            }
            const Type = if (comptime @TypeOf(tid_or_type) == TypeId) TypeId else tid_or_type;
            @compileError("invalid type " ++ @typeName(Type) ++ ": must be a TypeId or a type in the registered list");
        }

        pub inline fn getName(tid_or_type: anytype) [:0]const u8 {
            if (comptime @TypeOf(tid_or_type) == TypeId) {
                return TypeIdNameMap.get(tid_or_type);
            } else if (comptime isRegisteredType(tid_or_type)) {
                return @typeName(tid_or_type);
            }
            @compileError("invalid type " ++
                @typeName(@TypeOf(tid_or_type)) ++
                ": must be a TypeId or a type in the registered list");
        }

        pub const Iterator = struct {
            index: usize = 0,
            pub fn init() @This() {
                return .{};
            }
            pub fn nextType(self: *@This()) ?type {
                if (self.index >= Len) return null;
                const T = Types[self.index];
                self.index += 1;
                return T;
            }
            pub fn nextTypeNonEmpty(self: *@This()) ?type {
                inline while (self.nextType()) |Type| {
                    if (comptime @sizeOf(Type) != 0) {
                        return Type;
                    }
                }
                return null;
            }
            pub fn nextTypeId(self: *@This()) ?TypeId {
                if (self.index >= Len) return null;
                const tid = TypeIds[self.index];
                self.index += 1;
                return tid;
            }
            pub fn nextTypeIdNonEmpty(self: *@This()) ?TypeId {
                while (self.nextTypeId()) |idx| {
                    const size = Sizes[idx];
                    if (size != 0) {
                        return TypeIds[idx];
                    }
                }
                return null;
            }
        };
    };
}

test TypeHasher {
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };

    const signature = TypeHasher(&.{ typeA, typeC, typeD, typeE });
    try std.testing.expect(signature.isRegisteredType(typeA));
    try std.testing.expect(!signature.isRegisteredType(typeB));
    try std.testing.expect(signature.isRegisteredType(typeC));
    try std.testing.expect(signature.isRegisteredType(typeD));
    try std.testing.expect(signature.isRegisteredType(typeE));
}
