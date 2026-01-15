const std = @import("std");
const sparseset = @import("sparse_set.zig");

fn checkForNameCollision(comptime ComponentTypes: []const type) void {
    inline for (ComponentTypes, 0..) |T, i| {
        inline for (ComponentTypes[i + 1 ..]) |U| {
            if (std.mem.eql(u8, @typeName(T), @typeName(U))) {
                @compileError("Type name collision detected between '" ++
                    @typeName(T) ++ "' and '" ++ @typeName(U) ++ "'. Mind changing one of the components name? @typeName is the only way to generate unique hashes at comptime. If you don't get it, what about a read? https://ziggit.dev/t/type-id-comptime-generation/10956/8");
            }
        }
    }
}

fn initComponentTypeId(comptime ComponentTypes: []const type) type {
    checkForNameCollision(ComponentTypes);
    var fields: [ComponentTypes.len]std.builtin.Type.EnumField = undefined;
    for (ComponentTypes, 0..) |Component, i| {
        fields[i] = .{
            .name = @typeName(Component),
            // yup, this is the hash
            .value = i,
        };
    }
    return @Type(.{ .@"enum" = .{
        .is_exhaustive = true,
        .tag_type = std.math.IntFittingRange(0, ComponentTypes.len),
        .decls = &.{},
        .fields = &fields,
    } });
}

pub fn Components(comptime ComponentTypes: []const type) type {
    return struct {
        /// enum that will be used to make typeIds (tid) typed
        /// EVERY tid should be ComponentTypeId
        pub const ComponentTypeId = initComponentTypeId(ComponentTypes);

        /// for functions receiving a tid, use a static enum map to return info in O(1)
        const TypeIdSizeMap = TypeIdSizeMap: {
            var map = std.EnumArray(ComponentTypeId, usize).initUndefined();
            for (ComponentTypes) |Component| {
                const component_type_id = std.meta.stringToEnum(ComponentTypeId, @typeName(Component)).?;
                map.set(component_type_id, @sizeOf(Component));
            }
            break :TypeIdSizeMap map;
        };
        /// for functions receiving a tid, use a static enum map to return info in O(1)
        const TypeIdIndexMap = TypeIdIndexMap: {
            var map = std.EnumArray(ComponentTypeId, usize).initUndefined();
            for (ComponentTypes, 0..) |Component, i| {
                const component_type_id = std.meta.stringToEnum(ComponentTypeId, @typeName(Component)).?;
                map.set(component_type_id, i);
            }
            break :TypeIdIndexMap map;
        };

        /// for bitset iterator, just use an array to get tid
        const TypeIds = TypeIds: {
            var type_ids: [ComponentTypes.len]ComponentTypeId = undefined;
            for (ComponentTypes, 0..) |ComponentType, i| {
                type_ids[i] = hash(ComponentType);
            }
            break :TypeIds type_ids;
        };
        /// for bitset iterator, just use an array to get size
        const Sizes = Sizes: {
            var sizes: [ComponentTypes.len]usize = undefined;
            for (ComponentTypes, 0..) |ComponentType, i| {
                sizes[i] = @sizeOf(ComponentType);
            }
            break :Sizes sizes;
        };

        const BitSet = std.bit_set.StaticBitSet(ComponentTypes.len);
        /// this is where archetype signatures are stored. Comptime static maps and arrays
        /// store the info given a tid
        bitset: BitSet,

        fn componentIndex(comptime T: type) usize {
            if (comptime std.mem.indexOfScalar(type, ComponentTypes, T)) |idx| {
                return idx;
            }
            @compileError("This type was not registered as a component");
        }

        pub fn isComponent(comptime T: type) bool {
            return comptime std.mem.indexOfScalar(type, ComponentTypes, T) != null;
        }

        pub fn init(comptime Types: []const type) @This() {
            const bitset = comptime bitset: {
                var set = BitSet.initEmpty();
                for (Types) |Type| {
                    const idx = componentIndex(Type);
                    set.set(idx);
                }
                break :bitset set;
            };
            return .{
                .bitset = bitset,
            };
        }

        pub fn hash(comptime Component: type) ComponentTypeId {
            return std.meta.stringToEnum(ComponentTypeId, @typeName(Component)).?;
        }

        pub fn add(self: *@This(), tid_or_component: anytype) void {
            if (comptime @TypeOf(tid_or_component) == type) {
                self.bitset.set(comptime componentIndex(tid_or_component));
                return;
            } else if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                self.bitset.set(TypeIdIndexMap.get(tid_or_component));
                return;
            }
            @compileError("'add' can only be called using a TypeId or Component type");
        }

        pub fn remove(self: *@This(), tid_or_component: anytype) void {
            if (comptime @TypeOf(tid_or_component) == type) {
                self.bitset.unset(comptime componentIndex(tid_or_component));
                return;
            } else if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                self.bitset.unset(TypeIdIndexMap.get(tid_or_component));
                return;
            }
            @compileError("'remove' can only be called using a TypeId or Component type");
        }

        pub fn has(self: *@This(), tid_or_component: anytype) bool {
            if (comptime @TypeOf(tid_or_component) == type) {
                return self.bitset.isSet(comptime componentIndex(tid_or_component));
            } else if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                return self.bitset.isSet(TypeIdIndexMap.get(tid_or_component));
            }
            @compileError("'has' can only be called using a TypeId or Component type");
        }

        pub fn getSize(tid: ComponentTypeId) usize {
            return TypeIdSizeMap.get(tid);
        }

        pub fn iterator(self: @This()) Iterator {
            return Iterator.init(self.bitset);
        }

        const Iterator = struct {
            iter: BitSet.Iterator(.{ .kind = .set, .direction = .forward }),
            pub fn init(set: BitSet) @This() {
                return .{
                    .iter = set.iterator(.{ .kind = .set, .direction = .forward }),
                };
            }
            pub fn nextComponent(self: *@This()) ?type {
                if (self.iter.next()) |idx| {
                    return ComponentTypes[idx];
                }
                return null;
            }
            pub fn nextComponentNonEmpty(self: *@This()) ?type {
                inline while (self.typedNext()) |Component| {
                    if (comptime @sizeOf(Component) != 0) {
                        return Component;
                    }
                }
                return null;
            }
            pub fn nextTypeId(self: *@This()) ?ComponentTypeId {
                if (self.iter.next()) |idx| {
                    return TypeIds[idx];
                }
                return null;
            }
            pub fn nextTypeIdNonEmpty(self: *@This()) ?ComponentTypeId {
                while (self.iter.next()) |idx| {
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

test Components {
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };

    var signature = Components(&.{ typeA, typeB, typeC, typeD, typeE }).init(&.{ typeA, typeC, typeD, typeE });
    try std.testing.expect(signature.has(typeA));
    try std.testing.expect(!signature.has(typeB));
    try std.testing.expect(signature.has(typeC));
    try std.testing.expect(signature.has(typeD));
    try std.testing.expect(signature.has(typeE));
}
