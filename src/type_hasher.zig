const std = @import("std");

fn checkForNameCollision(comptime Types: []const type) void {
    inline for (Types, 0..) |T, i| {
        inline for (Types[i + 1 ..]) |U| {
            if (std.mem.eql(u8, @typeName(T), @typeName(U))) {
                @compileError("Type name collision detected between '" ++
                    @typeName(T) ++ "' and '" ++ @typeName(U) ++ "'. Mind changing one of the types name? @typeName is the only way to generate unique hashes at comptime. If you don't get it, what about a read? https://ziggit.dev/t/type-id-comptime-generation/10956/8");
            }
        }
    }
}

fn initTypeId(comptime Types: []const type) type {
    checkForNameCollision(Types);
    var fields: [Types.len]std.builtin.Type.EnumField = undefined;
    for (Types, 0..) |Type, i| {
        fields[i] = .{
            .name = @typeName(Type),
            // yup, this is the hash
            .value = i,
        };
    }
    return @Type(.{ .@"enum" = .{
        .is_exhaustive = true,
        .tag_type = std.math.IntFittingRange(0, Types.len),
        .decls = &.{},
        .fields = &fields,
    } });
}

pub fn TypeHasher(comptime Types: []const type) type {
    return struct {
        /// enum that will be used to make typeIds (tid) typed
        /// EVERY tid should be TypeId
        pub const TypeId = initTypeId(Types);
        pub const Len = Types.len;

        pub const Union = Union: {
            @setEvalBranchQuota(10000);
            var fields: [Len]std.builtin.Type.UnionField = undefined;
            for (Types, 0..) |Type, i| {
                fields[i] = std.builtin.Type.UnionField{
                    .alignment = @alignOf(Type),
                    .name = @typeName(Type),
                    .type = Type,
                };
            }
            break :Union @Type(.{
                .@"union" = .{
                    .decls = &.{},
                    .fields = &fields,
                    .tag_type = TypeId,
                    .layout = .auto,
                },
            });
        };

        /// for functions receiving a tid, use a static enum map to return info in O(1)
        const TypeIdSizeMap = TypeIdSizeMap: {
            @setEvalBranchQuota(10000);
            var map = std.EnumArray(TypeId, usize).initUndefined();
            for (Types) |Type| {
                const type_id = std.meta.stringToEnum(TypeId, @typeName(Type)).?;
                map.set(type_id, @sizeOf(Type));
            }
            break :TypeIdSizeMap map;
        };
        const TypeIdAlignmentMap = TypeIdAlignmentMap: {
            @setEvalBranchQuota(10000);
            var map = std.EnumArray(TypeId, usize).initUndefined();
            for (Types) |Type| {
                const type_id = std.meta.stringToEnum(TypeId, @typeName(Type)).?;
                map.set(type_id, @alignOf(Type));
            }
            break :TypeIdAlignmentMap map;
        };
        /// for functions receiving a tid, use a static enum map to return info in O(1)
        const TypeIdIndexMap = TypeIdIndexMap: {
            @setEvalBranchQuota(10000);
            var map = std.EnumArray(TypeId, usize).initUndefined();
            for (Types, 0..) |Type, i| {
                const type_id = std.meta.stringToEnum(TypeId, @typeName(Type)).?;
                map.set(type_id, i);
            }
            break :TypeIdIndexMap map;
        };

        pub const TypeIds = TypeIds: {
            @setEvalBranchQuota(10000);
            var type_ids: [Types.len]TypeId = undefined;
            for (Types, 0..) |Type, i| {
                type_ids[i] = hash(Type);
            }
            break :TypeIds type_ids;
        };
        pub const Sizes = Sizes: {
            @setEvalBranchQuota(10000);
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
                        @compileError("Pointer doesn't point to a registered type");
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

        pub inline fn checkSize(tid_or_type: anytype) void {
            checkType(tid_or_type);
            if (comptime @TypeOf(tid_or_type) == TypeId) {
                std.debug.assert(@This().getSize(tid_or_type) != 0);
            } else if (comptime @This().isRegisteredType(tid_or_type)) {
                if (comptime @sizeOf(tid_or_type) == 0) {
                    @compileError("function called with zero-sized type '" ++ @typeName(tid_or_type) ++ "' as argument!");
                }
            }
        }

        pub inline fn getSize(tid_or_type: anytype) usize {
            if (comptime @TypeOf(tid_or_type) == TypeId) {
                return TypeIdSizeMap.get(tid_or_type);
            } else if (comptime isRegisteredType(tid_or_type)) {
                return @sizeOf(tid_or_type);
            }
            @compileError("invalid type " ++ @typeName(@TypeOf(tid_or_type)) ++ ": must be a TypeId or a type in the registered list");
        }

        pub inline fn getAlignment(tid_or_type: anytype) usize {
            if (comptime @TypeOf(tid_or_type) == TypeId) {
                return TypeIdAlignmentMap.get(tid_or_type);
            } else if (comptime isRegisteredType(tid_or_type)) {
                return @alignOf(tid_or_type);
            }
            @compileError("invalid type " ++ @typeName(@TypeOf(tid_or_type)) ++ ": must be a TypeId or a type in the registered list");
        }

        pub inline fn getIndex(tid_or_type: anytype) usize {
            if (comptime @TypeOf(tid_or_type) == TypeId) {
                return TypeIdIndexMap.get(tid_or_type);
            } else if (comptime isRegisteredType(tid_or_type)) {
                if (comptime std.mem.indexOfScalar(type, Types, tid_or_type)) |idx| {
                    return idx;
                }
            }
            @compileError("invalid type " ++ @typeName(@TypeOf(tid_or_type)) ++ ": must be a TypeId or a type in the registered list");
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
                while (self.iter.nextTypeId()) |idx| {
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
