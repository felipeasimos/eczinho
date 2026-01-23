const std = @import("std");
const TypeHasher = @import("type_hasher.zig").TypeHasher;

pub fn Components(comptime ComponentTypes: []const type) type {
    return struct {
        const Hasher = TypeHasher(ComponentTypes);
        pub const ComponentTypeId = Hasher.TypeId;
        pub const Union = Hasher.Union;
        pub const getCanonicalType = Hasher.getCanonicalType;
        pub const getAlignment = Hasher.getAlignment;
        pub const getSize = Hasher.getSize;
        pub const checkSize = Hasher.checkSize;
        pub const checkType = Hasher.checkType;
        pub const getAsUnion = Hasher.getAsUnion;
        pub const isComponent = Hasher.isRegisteredType;
        pub const getAccessType = Hasher.getAccessType;
        pub const hash = Hasher.hash;

        const BitSet = std.bit_set.StaticBitSet(ComponentTypes.len);
        /// this is where archetype signatures are stored. Comptime static maps and arrays
        /// store the info given a tid
        bitset: BitSet,

        pub fn init(comptime Types: []const type) @This() {
            const bitset = comptime bitset: {
                var set = BitSet.initEmpty();
                for (Types) |Type| {
                    const idx = Hasher.getIndex(Type);
                    set.set(idx);
                }
                break :bitset set;
            };
            return .{
                .bitset = bitset,
            };
        }

        pub fn add(self: *@This(), tid_or_component: anytype) void {
            Hasher.checkType(tid_or_component);
            self.bitset.set(Hasher.getIndex(tid_or_component));
        }

        pub fn remove(self: *@This(), tid_or_component: anytype) void {
            Hasher.checkType(tid_or_component);
            self.bitset.unset(Hasher.getIndex(tid_or_component));
        }

        pub fn has(self: *@This(), tid_or_component: anytype) bool {
            Hasher.checkType(tid_or_component);
            return self.bitset.isSet(Hasher.getIndex(tid_or_component));
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
                inline while (self.nextComponent()) |Component| {
                    if (comptime @sizeOf(Component) != 0) {
                        return Component;
                    }
                }
                return null;
            }
            pub fn nextTypeId(self: *@This()) ?ComponentTypeId {
                if (self.iter.next()) |idx| {
                    return Hasher.TypeIds[idx];
                }
                return null;
            }
            pub fn nextTypeIdNonEmpty(self: *@This()) ?ComponentTypeId {
                while (self.iter.next()) |idx| {
                    const size = Hasher.Sizes[idx];
                    if (size != 0) {
                        return Hasher.TypeIds[idx];
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
