const std = @import("std");

const page_size: usize = std.heap.pageSize();

pub const SparseSetOptions = struct {
    T: type,
    /// mask to get the page number from the data
    PageMask: usize = 4096,
    RemoveEmptyPages: bool = false,
};

pub fn SparseSet(comptime options: SparseSetOptions) type {
    const data_bits = @typeInfo(options.T).int.bits;
    const usize_bits = @typeInfo(usize).int.bits;

    const Page = struct {
        num_items: usize = 0,
        data: []options.T,
    };

    return struct {
        const Null = std.math.maxInt(options.T);

        sparse: std.ArrayList(?Page) = .empty,
        dense: std.ArrayList(options.T) = .empty,
        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.sparse.items) |page_opt| {
                if (page_opt) |p| {
                    self.allocator.free(p.data);
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
            return p < self.sparse.items.len and self.sparse.items[p] != null and self.sparse.items[p].?.data[self.offset(data)] != Null;
        }

        /// get page
        fn getPage(self: *@This(), page_index: usize, comptime create: bool) !*Page {
            if (comptime create) {
                if (page_index >= self.sparse.items.len) {
                    const diff = page_index - self.sparse.items.len + 1;
                    try self.sparse.appendNTimes(self.allocator, null, diff);
                }

                if (self.sparse.items[page_index] == null) {
                    const new_page_data = try self.allocator.alloc(options.T, page_size);
                    @memset(new_page_data, Null);
                    self.sparse.items[page_index] = Page{
                        .data = new_page_data,
                        .num_items = 0,
                    };
                }
            }

            return &self.sparse.items[page_index].?;
        }

        fn getElementSparsePtr(self: *@This(), data: options.T, comptime create: bool) !*options.T {
            const p = try self.getPage(self.page(data), create);
            return &p.data[self.offset(data)];
        }

        /// adds integer to set. Nothing happens if integer is already contained
        pub fn add(self: *@This(), data: options.T) !void {
            std.debug.assert(!self.contains(data));
            std.debug.assert(data != Null);
            const p = try self.getPage(self.page(data), true);
            p.data[self.offset(data)] = toData(self.dense.items.len);
            if (comptime options.RemoveEmptyPages) {
                p.num_items += 1;
            }
            try self.dense.append(self.allocator, data);
        }

        // remove integer from set. Nothing happens if integer is already not contained
        pub fn remove(self: *@This(), data: options.T) !void {
            std.debug.assert(self.contains(data));
            std.debug.assert(data != Null);

            const p = try self.getPage(self.page(data), false);
            const last_ptr = try self.getElementSparsePtr(self.dense.getLast(), false);
            // 1. set 'data' in dense array to be the value of the last element in the dense array
            const dense_index = p.data[self.offset(data)];
            last_ptr.* = dense_index;
            // 2. set 'data' in the sparse array to set to Null
            p.data[self.offset(data)] = Null;
            if (comptime options.RemoveEmptyPages) {
                p.num_items -= 1;
                if (p.num_items == 0) {
                    self.allocator.free(self.sparse.items[self.page(data)].?.data);
                    self.sparse.items[self.page(data)] = null;
                }
            }

            _ = self.dense.swapRemove(dense_index);
        }
    };
}

test "sparseset init" {
    var _u1 = SparseSet(.{ .T = u1, .RemoveEmptyPages = true }).init(std.testing.allocator);
    try std.testing.expectEqual(0, _u1.len());
}

test "u2 sparseset contains" {
    var _u2 = SparseSet(.{ .T = u2, .RemoveEmptyPages = true }).init(std.testing.allocator);
    defer _u2.deinit();

    try std.testing.expect(!_u2.contains(0));
    try std.testing.expect(!_u2.contains(1));
}

test "u2 sparseset add" {
    var _u2 = SparseSet(.{ .T = u2, .RemoveEmptyPages = true }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try std.testing.expect(_u2.contains(0));
    try std.testing.expectEqual(1, _u2.len());
}

test "u2 sparseset multiple add" {
    var _u2 = SparseSet(.{ .T = u2, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u2 = SparseSet(.{ .T = u2, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u2 = SparseSet(.{ .T = u2, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u2 = SparseSet(.{ .T = u2, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u2 = SparseSet(.{ .T = u2, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u40 = SparseSet(.{ .T = u40, .RemoveEmptyPages = true }).init(std.testing.allocator);
    defer _u40.deinit();

    try std.testing.expect(!_u40.contains(0));
    try std.testing.expect(!_u40.contains(1));
}

test "u40 sparseset add" {
    var _u40 = SparseSet(.{ .T = u40, .RemoveEmptyPages = true }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try std.testing.expect(_u40.contains(0));
    try std.testing.expectEqual(1, _u40.len());
}

test "u40 sparseset multiple add" {
    var _u40 = SparseSet(.{ .T = u40, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u40 = SparseSet(.{ .T = u40, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u40 = SparseSet(.{ .T = u40, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u40 = SparseSet(.{ .T = u40, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u40 = SparseSet(.{ .T = u40, .RemoveEmptyPages = true }).init(std.testing.allocator);
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
    var _u40 = SparseSet(.{ .T = u40, .RemoveEmptyPages = true }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(32);
    try _u40.add(64);

    try std.testing.expectEqual(3, _u40.len());
    try std.testing.expect(_u40.contains(64));
    try std.testing.expect(_u40.contains(32));
    try std.testing.expect(_u40.contains(0));
}
