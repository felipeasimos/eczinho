pub const std = @import("std");

pub const TypeId = *const struct {
    _: u8,
};

pub inline fn hash(comptime T: type) TypeId {
    return &struct {
        comptime {
            _ = T;
        }
        const id: @typeInfo(TypeId).pointer.child = undefined;
    }.id;
}

test hash {
    // ints
    try std.testing.expectEqual(hash(u8), hash(u8));
    try std.testing.expectEqual(hash(u16), hash(u16));
    try std.testing.expectEqual(hash(u7), hash(u7));

    try std.testing.expect(hash(u8) != hash(u16));
    try std.testing.expect(hash(u8) != hash(u7));
    try std.testing.expect(hash(u7) != hash(u16));

    // tuples
    try std.testing.expectEqual(hash(struct { bool, u7 }), hash(struct { bool, u7 }));

    try std.testing.expect(hash(struct { bool, u7 }) != hash(struct { u7, bool }));

    // structs
    const TestStructA = struct { a: bool };
    const TestStructB = struct { a: bool };

    try std.testing.expectEqual(hash(TestStructA), hash(TestStructA));
    try std.testing.expectEqual(hash(TestStructB), hash(TestStructB));

    try std.testing.expect(hash(TestStructA) != hash(TestStructB));
}
