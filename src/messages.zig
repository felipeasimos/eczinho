const std = @import("std");

pub fn Messages(comptime T: type) type {
    return struct {
        /// we read only from this buffer
        source_buffer: std.ArrayList(T) = .empty,
        /// we write only to this buffer
        sink_buffer: std.ArrayList(T) = .empty,
        allocator: std.mem.Allocator,
        /// number of events of type T ever written
        count: usize = 0,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
            };
        }
        pub fn deinit(self: *@This()) void {
            self.source_buffer.deinit(self.allocator);
            self.sink_buffer.deinit(self.allocator);
        }
        /// swap buffers, logically making the previous writes readable and
        /// clearing the write buffer
        pub fn swap(self: *@This()) void {
            self.source_buffer.deinit(self.allocator);
            self.source_buffer = self.sink_buffer;
            self.sink_buffer = .empty;
        }
        pub fn write(self: *@This(), event: T) !void {
            try self.sink_buffer.append(self.allocator, event);
            self.count += 1;
        }
        inline fn firstReadableId(self: *@This()) usize {
            return self.count - self.sink_buffer.items.len - self.source_buffer.items.len;
        }
        inline fn readIndexCap(self: *@This()) usize {
            return self.count - self.sink_buffer.items.len;
        }
        /// update index to fall in a valid range,
        /// bumping it up to the first readable index if it falls behind
        fn normalize(self: *@This(), index_ptr: *usize) usize {
            const first_readable_index = self.firstReadableId();
            if (index_ptr.* < first_readable_index) {
                index_ptr.* = first_readable_index;
            }
            return index_ptr.*;
        }
        pub fn remaining(self: *@This(), index_ptr: *usize) usize {
            const index = self.normalize(index_ptr);
            return self.readIndexCap() - index;
        }
        pub fn readOne(self: *@This(), index_ptr: *usize) ?T {
            const index = self.normalize(index_ptr);
            if (index >= self.readIndexCap()) return null;
            const raw_index = index - self.firstReadableId();
            index_ptr.* += 1;
            return self.source_buffer.items[raw_index];
        }
        pub fn clear(self: *@This(), index_ptr: *usize) void {
            index_ptr.* = self.count - self.sink_buffer.items.len;
        }
    };
}

test Messages {
    var buf = Messages(u64).init(std.testing.allocator);
    defer buf.deinit();

    try std.testing.expectEqual(0, buf.sink_buffer.items.len);
    try std.testing.expectEqual(0, buf.source_buffer.items.len);
    try std.testing.expectEqual(0, buf.count);
    try buf.write(56);
    try std.testing.expectEqual(1, buf.sink_buffer.items.len);
    try std.testing.expectEqual(0, buf.source_buffer.items.len);
    try std.testing.expectEqual(1, buf.count);
    try buf.write(560);
    try std.testing.expectEqual(2, buf.sink_buffer.items.len);
    try std.testing.expectEqual(0, buf.source_buffer.items.len);
    try std.testing.expectEqual(2, buf.count);
    buf.swap();
    try std.testing.expectEqual(0, buf.sink_buffer.items.len);
    try std.testing.expectEqual(2, buf.source_buffer.items.len);
    try std.testing.expectEqual(2, buf.count);
    var i: usize = 0;
    try std.testing.expectEqual(56, buf.readOne(&i));
    try std.testing.expectEqual(560, buf.readOne(&i));
    try std.testing.expectEqual(null, buf.readOne(&i));
    buf.swap();
    try std.testing.expectEqual(0, buf.sink_buffer.items.len);
    try std.testing.expectEqual(0, buf.source_buffer.items.len);
    try std.testing.expectEqual(2, buf.count);
}
