const std = @import("std");

pub const Array = struct {
    data: std.ArrayList(u8),
    item_size: usize,
    pub fn init(item_size: usize) @This() {
        return .{ .data = .empty, .item_size = item_size };
    }
    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.data.deinit(gpa);
    }

    fn getU8Index(self: *@This(), index: usize) usize {
        return index * self.item_size;
    }
    pub fn len(self: *@This()) usize {
        return self.data.items.len / self.item_size;
    }
    pub fn get(self: *@This(), index: usize) []u8 {
        std.debug.assert(index < self.len());
        const u8_index = self.getU8Index(index);
        return self.data.items[u8_index .. u8_index + self.item_size];
    }
    pub fn getAs(self: *@This(), comptime T: type, index: usize) *T {
        return std.mem.bytesAsValue(T, self.get(index));
    }
    pub fn getConst(self: *@This(), comptime T: type, index: usize) T {
        return std.mem.bytesAsValue(T, self.get(index)).*;
    }
    pub fn append(self: *@This(), gpa: std.mem.Allocator, data: anytype) !void {
        try self.data.appendSlice(gpa, std.mem.asBytes(&data));
    }
    pub fn reserve(self: *@This(), gpa: std.mem.Allocator) !void {
        try self.data.appendNTimes(gpa, undefined, self.item_size);
    }
    pub fn removeLast(self: *@This()) void {
        std.debug.assert(self.len() > 0);
        self.data.items.len -= self.item_size;
    }
    pub fn swapRemove(self: *@This(), i: usize) void {
        if (self.len() - 1 == i) {
            self.removeLast();
            return;
        }
        @memcpy(self.get(i), self.get(self.len() - 1));
    }
};
