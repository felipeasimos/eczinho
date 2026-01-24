const std = @import("std");

pub fn EventBuffer(comptime T: type) type {
    return struct {
        previous: std.ArrayList(T) = .empty,
        current: std.ArrayList(T) = .empty,
        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
            };
        }
        pub fn deinit(self: *@This()) void {
            self.previous.deinit(self.allocator);
            self.current.deinit(self.allocator);
        }
        pub fn swap(self: *@This()) void {
            self.previous.deinit(self.allocator);
            self.previous = self.current;
            self.current = .empty;
        }
        pub fn len(self: *@This()) usize {
            return self.previous.items.len + self.current.items.len;
        }
        pub fn write(self: *@This(), event: T) !void {
            try self.current.append(self.allocator, event);
        }
        pub fn read(self: *@This(), index: usize) T {
            std.debug.assert(index < self.len());
            const previous_len = self.previous.items.len;
            if (index < previous_len) {
                return self.previous.items[index];
            }
            return self.current.items[index - previous_len];
        }
    };
}
