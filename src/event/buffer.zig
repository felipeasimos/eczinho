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
        pub fn remaining(self: *@This(), index: usize) usize {
            return self.read_count - index;
        }
        pub fn write(self: *@This(), _: T) !void {
            self.count += 1;
        }
        pub fn optRead(self: *@This(), index: usize) ?T {
            if (index < self.read_count) return self.read(index);
            return null;
        }
        pub fn read(self: *@This(), index: usize) T {
            std.debug.assert(index < self.read_count);
            return T{};
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
        pub fn remaining(self: *@This(), index: usize) usize {
            return self.count - self.sink_buffer.items.len - index;
        }
        fn isIndexAvailable(self: *@This(), index: usize) bool {
            const end_idx = self.count - self.sink_buffer.items.len;
            const start_idx = end_idx - self.source_buffer.items.len;
            return start_idx <= index and index < end_idx;
        }
        pub fn write(self: *@This(), event: T) !void {
            try self.sink_buffer.append(self.allocator, event);
            self.count += 1;
        }
        pub fn optRead(self: *@This(), index: usize) ?T {
            if (self.isIndexAvailable(index)) return self.read(index);
            return null;
        }
        inline fn toRawIndex(self: *@This(), index: usize) usize {
            std.debug.assert(self.isIndexAvailable(index));
            const start_idx = self.count - self.sink_buffer.items.len - self.source_buffer.items.len;
            const raw_index = index - start_idx;
            return raw_index;
        }
        pub fn read(self: *@This(), index: usize) T {
            const raw_index = self.toRawIndex(index);
            return self.source_buffer.items[raw_index];
        }
    };
}
