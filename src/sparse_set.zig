const std = @import("std");

const page_size: usize = std.heap.pageSize();

pub const SparseSetOptions = struct {
    T: type,
    /// mask to get the page number from the data
    PageMask: usize = 4096,
};

pub fn SparseSet(comptime options: SparseSetOptions) type {
    const data_bits = @typeInfo(options.T).int.bits;
    const usize_bits = @typeInfo(usize).int.bits;

    return struct {
        const Null = std.math.maxInt(options.T);

        sparse: std.ArrayList(?[]options.T) = .empty,
        dense: std.ArrayList(options.T) = .empty,
        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.sparse.items) |opt| {
                if (opt) |p| {
                    self.allocator.free(p);
                }
            }
            self.sparse.deinit(self.allocator);
            self.dense.deinit(self.allocator);
        }

        pub fn len(self: *@This()) usize {
            return self.dense.items.len;
        }

        pub fn page(_: *@This(), data: options.T) usize {
            return (toUsize(data) & options.PageMask) / page_size;
        }

        pub fn offset(_: *@This(), data: options.T) usize {
            return toUsize(data) & (page_size - 1);
        }

        fn toUsize(data: options.T) usize {
            if (data_bits > usize_bits) {
                return @truncate(data);
            }
            return @intCast(data);
        }

        fn toData(idx: usize) options.T {
            if (data_bits > usize_bits) {
                return @intCast(idx);
            }
            return @truncate(idx);
        }

        /// check if set already contains integer
        pub fn contains(self: *@This(), data: options.T) bool {
            const p = self.page(data);
            return p < self.sparse.items.len and self.sparse.items[p] != null and self.sparse.items[p].?[self.offset(data)] != Null;
        }

        /// get page, creating it if it doesn't exist
        fn getPage(self: *@This(), page_index: usize) ![]options.T {
            if (page_index >= self.sparse.items.len) {
                const diff = page_index - self.sparse.items.len + 1;
                try self.sparse.appendNTimes(self.allocator, null, diff);
            }

            if (self.sparse.items[page_index] == null) {
                const new_page = try self.allocator.alloc(options.T, page_size);
                @memset(new_page, Null);
                self.sparse.items[page_index] = new_page;
            }

            return self.sparse.items[page_index].?;
        }

        fn getElementSparsePtr(self: *@This(), data: options.T) !*options.T {
            const p = try self.getPage(self.page(data));
            return &p[self.offset(data)];
        }

        /// adds integer to set. Nothing happens if integer is already contained
        pub fn add(self: *@This(), data: options.T) !void {
            std.debug.assert(!self.contains(data));
            std.debug.assert(data != Null);
            const data_ptr = try self.getElementSparsePtr(data);
            data_ptr.* = toData(self.dense.items.len);
            try self.dense.append(self.allocator, data);
        }

        // remove integer from set. Nothing happens if integer is already not contained
        pub fn remove(self: *@This(), data: options.T) !void {
            std.debug.assert(self.contains(data));
            std.debug.assert(data != Null);

            const data_ptr = try self.getElementSparsePtr(data);
            const last_ptr = try self.getElementSparsePtr(self.dense.getLast());
            // 1. set 'data' in dense array to be the value of the last element in the dense array
            const dense_index = data_ptr.*;
            last_ptr.* = dense_index;
            // 2. set 'data' in the sparse array to set to Null
            data_ptr.* = Null;

            _ = self.dense.swapRemove(dense_index);
        }
    };
}

test "sparseset init" {
    var _u1 = SparseSet(.{ .T = u1 }).init(std.testing.allocator);
    try std.testing.expectEqual(0, _u1.len());
}

test "u2 sparseset contains" {
    var _u2 = SparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try std.testing.expect(!_u2.contains(0));
    try std.testing.expect(!_u2.contains(1));
}

test "u2 sparseset add" {
    var _u2 = SparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try std.testing.expect(_u2.contains(0));
    try std.testing.expectEqual(1, _u2.len());
}

test "u2 sparseset multiple add" {
    var _u2 = SparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try _u2.add(1);
    try std.testing.expect(_u2.contains(1));
    try std.testing.expectEqual(2, _u2.len());
    try _u2.add(2);
    try std.testing.expect(_u2.contains(2));
    try std.testing.expectEqual(3, _u2.len());
}

test "u2 sparseset multiple add out of order" {
    var _u2 = SparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try _u2.add(2);
    try std.testing.expect(_u2.contains(2));
    try std.testing.expectEqual(2, _u2.len());
    try _u2.add(1);
    try std.testing.expect(_u2.contains(1));
    try std.testing.expectEqual(3, _u2.len());
}

test "u2 sparseset multiple add redundant" {
    var _u2 = SparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try _u2.add(2);
    try std.testing.expect(_u2.contains(2));
    try std.testing.expectEqual(2, _u2.len());
    try _u2.add(1);
    try std.testing.expect(_u2.contains(1));
    try std.testing.expectEqual(3, _u2.len());
}

test "u2 sparseset remove" {
    var _u2 = SparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(2);
    try _u2.add(0);
    try _u2.add(1);

    try _u2.remove(0);
    try std.testing.expectEqual(2, _u2.len());
    try std.testing.expect(!_u2.contains(0));
    try std.testing.expect(_u2.contains(1));
    try std.testing.expect(_u2.contains(2));
}

test "u2 sparseset multiple remove" {
    var _u2 = SparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(2);
    try _u2.add(0);
    try _u2.add(1);

    try _u2.remove(0);
    try _u2.remove(2);
    try std.testing.expectEqual(1, _u2.len());
    try std.testing.expect(!_u2.contains(0));
    try std.testing.expect(_u2.contains(1));
    try std.testing.expect(!_u2.contains(2));
    try _u2.remove(1);
    try std.testing.expectEqual(0, _u2.len());
}

test "u40 sparseset contains" {
    var _u40 = SparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try std.testing.expect(!_u40.contains(0));
    try std.testing.expect(!_u40.contains(1));
}

test "u40 sparseset add" {
    var _u40 = SparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try std.testing.expect(_u40.contains(0));
    try std.testing.expectEqual(1, _u40.len());
}

test "u40 sparseset multiple add" {
    var _u40 = SparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(1);
    try std.testing.expect(_u40.contains(1));
    try std.testing.expectEqual(2, _u40.len());
    try _u40.add(2);
    try std.testing.expect(_u40.contains(2));
    try std.testing.expectEqual(3, _u40.len());
}

test "u40 sparseset multiple add out of order" {
    var _u40 = SparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(2);
    try std.testing.expect(_u40.contains(2));
    try std.testing.expectEqual(2, _u40.len());
    try _u40.add(1);
    try std.testing.expect(_u40.contains(1));
    try std.testing.expectEqual(3, _u40.len());
}

test "u40 sparseset multiple add redundant" {
    var _u40 = SparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(2);
    try std.testing.expect(_u40.contains(2));
    try std.testing.expectEqual(2, _u40.len());
    try _u40.add(1);
    try std.testing.expect(_u40.contains(1));
    try std.testing.expectEqual(3, _u40.len());
}

test "u40 sparseset remove" {
    var _u40 = SparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(2);
    try _u40.add(0);
    try _u40.add(1);

    try _u40.remove(0);
    try std.testing.expectEqual(2, _u40.len());
    try std.testing.expect(!_u40.contains(0));
    try std.testing.expect(_u40.contains(1));
    try std.testing.expect(_u40.contains(2));
}

test "u40 sparseset multiple remove" {
    var _u40 = SparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(2);
    try _u40.add(0);
    try _u40.add(1);

    try _u40.remove(0);
    try _u40.remove(2);
    try std.testing.expectEqual(1, _u40.len());
    try std.testing.expect(!_u40.contains(0));
    try std.testing.expect(_u40.contains(1));
    try std.testing.expect(!_u40.contains(2));
    try _u40.remove(1);
    try std.testing.expectEqual(0, _u40.len());
}

test SparseSet {
    var _u40 = SparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(32);
    try _u40.add(64);

    try std.testing.expectEqual(3, _u40.len());
    try std.testing.expect(_u40.contains(64));
    try std.testing.expect(_u40.contains(32));
    try std.testing.expect(_u40.contains(0));
}
