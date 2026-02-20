const std = @import("std");

const Messages = @import("../messages.zig").Messages;

pub fn EventBuffer(comptime T: type) type {
    if (@sizeOf(T) == 0) {
        return EventIndexBuffer(T);
    } else {
        return Messages(T);
    }
}

fn EventIndexBuffer(comptime T: type) type {
    return struct {
        // max number of written events
        count: usize = 0,
        // last readable id
        last_readable_count: usize = 0,
        // first avaiable readable event
        first_readable_id: usize = 0,
        pub inline fn init(_: std.mem.Allocator) @This() {
            return .{};
        }
        pub inline fn deinit(self: *@This()) void {
            _ = self;
        }
        pub inline fn swap(self: *@This()) void {
            self.first_readable_id = self.last_readable_count;
            self.last_readable_count = self.count;
        }
        pub inline fn write(self: *@This(), _: T) !void {
            self.count += 1;
        }
        inline fn normalize(self: *@This(), index_ptr: *usize) void {
            if (index_ptr.* < self.first_readable_id) {
                index_ptr.* = self.first_readable_id;
            }
        }
        pub inline fn remaining(self: *@This(), index_ptr: *usize) usize {
            self.normalize(index_ptr);
            return self.last_readable_count - index_ptr.*;
        }
        pub inline fn readOne(self: *@This(), index_ptr: *usize) T {
            std.debug.assert(index_ptr.* < self.last_readable_count);
            self.normalize(index_ptr);
            index_ptr.* += 1;
            return T{};
        }
        pub inline fn clear(self: *@This(), index_ptr: *usize) void {
            index_ptr.* = self.last_readable_count;
        }
    };
}

test EventIndexBuffer {
    const ZST = struct {};
    var buf = EventIndexBuffer(ZST).init(std.testing.allocator);
    defer buf.deinit();

    try buf.write(.{});
    try buf.write(.{});
    try buf.write(.{});

    var cursor: usize = 0;
    try std.testing.expectEqual(0, buf.remaining(&cursor));
    buf.swap();
    try std.testing.expectEqual(3, buf.remaining(&cursor));

    try std.testing.expectEqual(ZST{}, buf.readOne(&cursor));
    try std.testing.expectEqual(2, buf.remaining(&cursor));
    buf.clear(&cursor);

    try std.testing.expectEqual(0, buf.remaining(&cursor));
}
