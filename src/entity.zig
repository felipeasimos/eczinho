const std = @import("std");

pub const EntityOptions = struct {
    index_bits: usize,
    version_bits: usize,
    pub const small: @This() = .{ .index_bits = 12, .version_bits = 4 };
    pub const medium: @This() = .{ .index_bits = 20, .version_bits = 12 };
    pub const large: @This() = .{ .index_bits = 32, .version_bits = 32 };
};

pub fn EntityTypeFactory(comptime options: EntityOptions) type {
    const total_bits = options.index_bits + options.version_bits;
    const EntityBackingInt = std.meta.Int(.unsigned, total_bits);

    return packed struct(EntityBackingInt) {
        pub const Index = std.meta.Int(.unsigned, options.index_bits);
        pub const Version = std.meta.Int(.unsigned, options.version_bits);

        index: Index,
        version: Version,
    };
}

test EntityTypeFactory {
    const Small = EntityTypeFactory(.small);
    const Medium = EntityTypeFactory(.medium);
    const Large = EntityTypeFactory(.large);

    try std.testing.expectEqual(Small.Index, u12);
    try std.testing.expectEqual(Medium.Index, u20);
    try std.testing.expectEqual(Large.Index, u32);

    try std.testing.expectEqual(Small.Version, u4);
    try std.testing.expectEqual(Medium.Version, u12);
    try std.testing.expectEqual(Large.Version, u32);
}
