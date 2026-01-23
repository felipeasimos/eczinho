const std = @import("std");
const TypeHasher = @import("../type_hasher.zig").TypeHasher;

pub fn Resources(comptime ResourceTypes: []const type) type {
    return struct {
        const Hasher = TypeHasher(ResourceTypes);
        pub const ResourceTypeId = Hasher.TypeId;
        pub const Union = Hasher.Union;
        pub const getCanonicalType = Hasher.getCanonicalType;
        pub const getAlignment = Hasher.getAlignment;
        pub const getSize = Hasher.getSize;
        pub const checkSize = Hasher.checkSize;
        pub const checkType = Hasher.checkType;
        pub const getAsUnion = Hasher.getAsUnion;
        pub const isResource = Hasher.isRegisteredType;
        pub const hash = Hasher.hash;
        pub const Iterator = Hasher.Iterator;
    };
}

test Resources {
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };

    const signature = Resources(&.{ typeA, typeC, typeD, typeE });
    try std.testing.expect(signature.isResource(typeA));
    try std.testing.expect(!signature.isResource(typeB));
    try std.testing.expect(signature.isResource(typeC));
    try std.testing.expect(signature.isResource(typeD));
    try std.testing.expect(signature.isResource(typeE));
}
