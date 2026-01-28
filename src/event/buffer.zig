const std = @import("std");

pub fn EventBuffer(comptime T: type) type {
    if (@sizeOf(T) == 0) {
        return EventIndexBuffer(T);
    } else {
        return EventArrayBuffer(T);
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

fn EventArrayBuffer(comptime T: type) type {
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
            return self.source_buffer.items[raw_index];
        }
        pub fn clear(self: *@This(), index_ptr: *usize) void {
            index_ptr.* = self.count - self.sink_buffer.items.len;
        }
    };
}

test EventArrayBuffer {
    var buf = EventArrayBuffer(u64).init(std.testing.allocator);
    defer buf.deinit();
}

test EventIndexBuffer {
    var buf = EventIndexBuffer(u64).init(std.testing.allocator);
    defer buf.deinit();
}
