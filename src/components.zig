const std = @import("std");

pub fn Components(comptime ComponentTypes: []const type) type {
    return struct {
        pub const BitSet = std.bit_set.StaticBitSet(ComponentTypes.len);

        pub fn componentIndex(comptime T: type) usize {
            if (comptime std.mem.indexOfScalar(type, ComponentTypes, T)) |idx| {
                return idx;
            }
            @compileError("This type was not registered as a component");
        }

        pub fn isComponent(comptime T: type) bool {
            const idx = std.mem.indexOfScalar(type, ComponentTypes, T);
            return idx != null;
        }

        pub fn init(comptime Types: []const type) BitSet {
            var bitset = BitSet.initEmpty();
            for (Types) |Type| {
                const idx = componentIndex(Type);
                bitset.set(idx);
            }
            return bitset;
        }
    };
}
