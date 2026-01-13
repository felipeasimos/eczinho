const std = @import("std");

pub const IteratorOptions = struct {
    T: type,
    reference: bool = false,
    reverse: bool = false,
};

pub fn Iterator(comptime options: IteratorOptions) type {
    const ReturnType = if (options.reference) *options.T else options.T;
    return struct {
        data: []options.T,
        pub fn init(data: []options.T) @This() {
            return .{
                .data = data,
            };
        }
        pub fn next(self: *@This()) ?ReturnType {
            if (self.data.len == 0) return null;
            const index = index: {
                if (comptime options.reverse) {
                    break :index self.data.len - 1;
                } else {
                    break :index 0;
                }
            };
            const curr = curr: {
                if (comptime options.reference) {
                    break :curr &self.data[index];
                } else {
                    break :curr self.data[index];
                }
            };
            if (comptime options.reverse) {
                self.data = self.data[0 .. self.data.len - 1];
            } else {
                self.data = self.data[1..];
            }
            return curr;
        }
    };
}

test Iterator {
    var data = [_]u8{ 1, 2, 3, 4 };
    var iter = Iterator(.{ .T = u8, .reverse = false, .reference = false }).init(&data);
    var i: u32 = 0;
    while (iter.next()) |d| {
        i += 1;
        try std.testing.expectEqual(i, d);
    }
    try std.testing.expectEqual(null, iter.next());
}

test "reverse iterator" {
    var data = [_]u8{ 1, 2, 3, 4 };
    var iter = Iterator(.{ .T = u8, .reverse = true, .reference = false }).init(&data);
    var i: u32 = 0;
    while (iter.next()) |d| {
        try std.testing.expectEqual(data.len - i, d);
        i += 1;
    }
    try std.testing.expectEqual(null, iter.next());
}

test "reference iterator" {
    var data = [_]u8{ 1, 2, 3, 4 };
    var iter = Iterator(.{ .T = u8, .reverse = false, .reference = true }).init(&data);
    var i: u32 = 0;
    while (iter.next()) |d| {
        try std.testing.expectEqual(&data[i], d);
        i += 1;
    }
    try std.testing.expectEqual(null, iter.next());
}

test "reverse reference iterator" {
    var data = [_]u8{ 1, 2, 3, 4 };
    var iter = Iterator(.{ .T = u8, .reverse = true, .reference = true }).init(&data);
    var i: u32 = 0;
    while (iter.next()) |d| {
        try std.testing.expectEqual(&data[data.len - i - 1], d);
        i += 1;
    }
    try std.testing.expectEqual(null, iter.next());
}
