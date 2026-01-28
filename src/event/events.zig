const std = @import("std");
const TypeHasher = @import("../type_hasher.zig").TypeHasher;

pub fn Events(comptime EventTypes: []const type, comptime AdditionalTypes: []const type) type {
    return struct {
        const Hasher = TypeHasher(EventTypes ++ AdditionalTypes);
        pub const EventTypeId = Hasher.TypeId;
        pub const Union = Hasher.Union;
        pub const Len = Hasher.Len;
        pub const getCanonicalType = Hasher.getCanonicalType;
        pub const getAlignment = Hasher.getAlignment;
        pub const getSize = Hasher.getSize;
        pub const getIndex = Hasher.getIndex;
        pub const checkSize = Hasher.checkSize;
        pub const checkType = Hasher.checkType;
        pub const getAsUnion = Hasher.getAsUnion;
        pub const isEvent = Hasher.isRegisteredType;
        pub const hash = Hasher.hash;
        pub const Iterator = Hasher.Iterator;
    };
}

test Events {
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };

    const signature = Events(&.{ typeA, typeC, typeD, typeE }, &.{});
    try std.testing.expect(signature.isEvent(typeA));
    try std.testing.expect(!signature.isEvent(typeB));
    try std.testing.expect(signature.isEvent(typeC));
    try std.testing.expect(signature.isEvent(typeD));
    try std.testing.expect(signature.isEvent(typeE));
}
