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
        count: usize = 0,
        read_count: usize = 0,
        pub fn init(_: std.mem.Allocator) @This() {
            return .{};
        }
        pub fn deinit(self: *@This()) void {
            _ = self;
        }
        pub fn swap(self: *@This()) void {
            self.read_count = self.count;
        }
        pub fn write(self: *@This(), _: T) !void {
            self.count += 1;
        }
        pub fn remaining(self: *@This(), index_ptr: *usize) usize {
            return self.read_count - index_ptr.*;
        }
        pub fn readOne(self: *@This(), index_ptr: *usize) T {
            std.debug.assert(index_ptr.* < self.read_count);
            return T{};
        }
        pub fn clear(self: *@This(), index_ptr: *usize) void {
            index_ptr.* = self.read_count;
        }
    };
}

test EventIndexBuffer {
    var buf = EventIndexBuffer(u64).init(std.testing.allocator);
    defer buf.deinit();
}
