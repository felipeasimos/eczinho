const std = @import("std");
const iter = @import("iter.zig");

pub fn Components(comptime ComponentTypes: []const type) type {
    return struct {
        pub const BitSet = std.bit_set.StaticBitSet(ComponentTypes.len);
        bitset: BitSet,

        pub fn comptimeBitSet(comptime Signature: []const type) BitSet {
            return init(Signature).bitset;
        }

        fn componentIndex(comptime T: type) usize {
            if (comptime std.mem.indexOfScalar(type, ComponentTypes, T)) |idx| {
                return idx;
            }
            @compileError("This type was not registered as a component");
        }

        pub fn isComponent(comptime T: type) bool {
            const idx = std.mem.indexOfScalar(type, ComponentTypes, T);
            return idx != null;
        }

        pub fn init(comptime Types: []const type) @This() {
            var bitset = BitSet.initEmpty();
            for (Types) |Type| {
                const idx = componentIndex(Type);
                bitset.set(idx);
            }
            return .{
                .bitset = bitset,
            };
        }

        pub fn iterator(self: *@This()) Iterator {
            return Iterator.init(self.*);
        }

        const Iterator = struct {
            iter: Iterator,
            pub fn init(set: BitSet) @This() {
                return .{ .iter = set.iterator() };
            }
            pub fn next(self: *@This()) ?type {
                if (self.iter.next()) |idx| {
                    return ComponentTypes[idx];
                }
                return null;
            }
        };
    };
}

test Components {}
