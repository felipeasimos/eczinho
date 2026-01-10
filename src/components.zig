const std = @import("std");

pub fn Components(comptime ComponentTypes: []type) type {
    return struct {
        pub const BitSet = std.bit_set.StaticBitSet(ComponentTypes.len);

        fn componentIndex(comptime T: type) usize {
            if (comptime std.mem.indexOfScalar(type, ComponentTypes, T)) |idx| {
                return idx;
            }
            @compileError("This type was not registered as a component");
        }

        fn isComponent(comptime T: type) bool {
            const idx = std.mem.indexOfScalar(type, ComponentTypes, T);
            return idx != null;
        }

        fn toBitset(comptime Types: []type) BitSet {
            var bitset = BitSet.initEmpty;
            for (Types) |Type| {
                const idx = componentIndex(Type);
                bitset.set(idx);
            }
            return bitset;
        }

        fn toComponentArray(comptime bitset: BitSet) [bitset.bit_length]type {
            var iter = bitset.iterator(.{});
            var components = .{};
            while (iter.next()) |idx| {
                components = components ++ .{ComponentTypes[idx]};
            }
            return components;
        }
    };
}
