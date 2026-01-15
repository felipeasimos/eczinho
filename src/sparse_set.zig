const std = @import("std");

var os_page_size: usize = std.heap.pageSize();

pub const SparseSetOptions = struct {
    T: type,
    /// mask to get the page number from the data
    PageMask: usize = 4096,
    /// if null, OS page size will be used
    PageSize: ?usize = null,
};

pub fn SparseSet(comptime options: SparseSetOptions) type {
    const data_bits = @typeInfo(options.T).int.bits;
    const usize_bits = @typeInfo(usize).int.bits;

    const Page = struct {
        data: []options.T,
    };

    return struct {
        const Null = std.math.maxInt(options.T);

        sparse: std.ArrayList(?Page) = .empty,
        dense: std.ArrayList(options.T) = .empty,
        allocator: std.mem.Allocator,
        page_size: usize,

        pub fn init(alloc: std.mem.Allocator) @This() {
            const psize = page_size: {
                if (comptime options.PageSize) |p| {
                    break :page_size p;
                }
                break :page_size os_page_size;
            };
            return .{
                .page_size = psize,
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

        pub fn getDenseIndex(self: *@This(), data: options.T) usize {
            std.debug.assert(self.contains(data));
            return self.getPage(self.page(data)).data[self.offset(data)];
        }

        fn page(self: *@This(), data: options.T) usize {
            return (toUsize(data) & options.PageMask) / self.page_size;
        }

        fn offset(self: *@This(), data: options.T) usize {
            return toUsize(data) & (self.page_size - 1);
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

        /// create page if it doesn't exists
        fn createPage(self: *@This(), page_index: usize) !void {
            if (page_index >= self.sparse.items.len) {
                const diff = page_index - self.sparse.items.len + 1;
                try self.sparse.appendNTimes(self.allocator, null, diff);
            }

            if (self.sparse.items[page_index] == null) {
                const new_page_data = try self.allocator.alloc(options.T, self.page_size);
                @memset(new_page_data, Null);
                self.sparse.items[page_index] = Page{
                    .data = new_page_data,
                };
            }
        }

        /// get page
        inline fn getPage(self: *@This(), page_index: usize) *Page {
            return &self.sparse.items[page_index].?;
        }

        /// adds integer to set. Nothing happens if integer is already contained
        pub fn add(self: *@This(), data: options.T) !void {
            std.debug.assert(!self.contains(data));
            std.debug.assert(data != Null);
            const page_index = self.page(data);
            try self.createPage(page_index);
            const p = self.getPage(page_index);
            p.data[self.offset(data)] = toData(self.dense.items.len);
            try self.dense.append(self.allocator, data);
        }

        fn getElementSparsePtr(self: *@This(), data: options.T) *options.T {
            const p = self.getPage(self.page(data));
            return &p.data[self.offset(data)];
        }

        // remove integer from set. Nothing happens if integer is already not contained
        // return dense index
        pub fn remove(self: *@This(), data: options.T) usize {
            std.debug.assert(self.contains(data));
            std.debug.assert(data != Null);

            const p = self.getPage(self.page(data));
            const last_ptr = self.getElementSparsePtr(self.dense.getLast());
            // 1. set 'data' in dense array to be the value of the last element in the dense array
            const dense_index = p.data[self.offset(data)];
            last_ptr.* = dense_index;
            // 2. set 'data' in the sparse array to set to Null
            p.data[self.offset(data)] = Null;

            _ = self.dense.swapRemove(dense_index);
            return dense_index;
        }

        pub fn items(self: *@This()) []options.T {
            return self.dense.items;
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

    try std.testing.expectEqual(1, _u2.remove(0));
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

    _ = _u2.remove(0);
    try std.testing.expectEqual(0, _u2.remove(2));
    try std.testing.expectEqual(1, _u2.len());
    try std.testing.expect(!_u2.contains(0));
    try std.testing.expect(_u2.contains(1));
    try std.testing.expect(!_u2.contains(2));
    try std.testing.expectEqual(0, _u2.remove(1));
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

    try std.testing.expectEqual(1, _u40.remove(0));
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

    _ = _u40.remove(0);
    try std.testing.expectEqual(0, _u40.remove(2));
    try std.testing.expectEqual(1, _u40.len());
    try std.testing.expect(!_u40.contains(0));
    try std.testing.expect(_u40.contains(1));
    try std.testing.expect(!_u40.contains(2));
    try std.testing.expectEqual(0, _u40.remove(1));
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
