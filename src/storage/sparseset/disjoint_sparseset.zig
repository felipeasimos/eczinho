const std = @import("std");

pub const DisjointSparseSetOptions = struct {
    K: type,
    V: type,
    /// if null, OS page size will be used
    PageSize: usize = 4096,
};

pub fn DisjointSparseSet(comptime options: DisjointSparseSetOptions) type {
    if (@popCount(options.PageSize) != 1) {
        @compileError("Page size is not a power of 2");
    }

    const key_bits = @typeInfo(options.K).int.bits;
    const usize_bits = @typeInfo(usize).int.bits;

    const KeyPage = struct {
        keys: []options.K,
    };

    return struct {
        pub const PageSize = options.PageSize;
        pub const PageMask = PageSize - 1;
        pub const K = options.K;
        pub const V = options.V;
        pub const empty: @This() = .{};

        const Null = std.math.maxInt(K);

        sparse: std.ArrayList(?KeyPage) = .empty,
        dense_keys: std.ArrayList(K) = .empty,
        dense_data: std.ArrayList(V) = .empty,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.sparse.items) |page_opt| {
                if (page_opt) |p| {
                    allocator.free(p.keys);
                }
            }
            self.sparse.deinit(allocator);
            self.dense_keys.deinit(allocator);
            self.dense_data.deinit(allocator);
        }

        pub fn len(self: *@This()) usize {
            return self.dense_keys.items.len;
        }

        fn getDenseIndex(self: *@This(), key: K) usize {
            std.debug.assert(self.contains(key));
            return self.getPage(getPageIndex(key)).keys[getPageOffset(key)];
        }

        fn getPageIndex(key: K) usize {
            return (toUsize(key) & PageMask) / PageSize;
        }

        fn getPageOffset(key: K) usize {
            return toUsize(key) & (PageMask);
        }

        fn toUsize(key: K) usize {
            if (key_bits > usize_bits) {
                return @truncate(key);
            }
            return @intCast(key);
        }

        fn toKey(idx: usize) K {
            if (key_bits > usize_bits) {
                return @intCast(idx);
            }
            return @truncate(idx);
        }

        /// check if set already contains integer
        pub fn contains(self: *@This(), data: K) bool {
            std.debug.assert(data != Null);
            const p = getPageIndex(data);
            return p < self.sparse.items.len and
                self.sparse.items[p] != null and
                self.sparse.items[p].?.keys[getPageOffset(data)] != Null;
        }

        /// create page if it doesn't exists
        fn createPage(self: *@This(), allocator: std.mem.Allocator, page_index: usize) !void {
            if (page_index >= self.sparse.items.len) {
                const diff = page_index - self.sparse.items.len + 1;
                try self.sparse.appendNTimes(allocator, null, diff);
            }

            if (self.sparse.items[page_index] == null) {
                const new_page_data = try allocator.alloc(K, PageSize);
                @memset(new_page_data, Null);
                self.sparse.items[page_index] = KeyPage{
                    .keys = new_page_data,
                };
            }
        }

        /// get page
        inline fn getPage(self: *@This(), page_index: usize) *KeyPage {
            return &self.sparse.items[page_index].?;
        }

        /// adds integer to set
        pub fn add(self: *@This(), allocator: std.mem.Allocator, key: K, value: V) !void {
            std.debug.assert(!self.contains(key));
            const page_index = getPageIndex(key);
            try self.createPage(allocator, page_index);
            const p = self.getPage(page_index);
            p.keys[getPageOffset(key)] = toKey(self.dense_keys.items.len);
            try self.dense_keys.append(allocator, key);
            try self.dense_data.append(allocator, value);
        }

        fn getElementSparsePtr(self: *@This(), data: K) *K {
            const p = self.getPage(getPageIndex(data));
            return &p.keys[getPageOffset(data)];
        }

        // remove integer from set. Nothing happens if integer is already not contained
        // return dense index
        pub fn remove(self: *@This(), data: K) usize {
            std.debug.assert(self.contains(data));

            const p = self.getPage(getPageIndex(data));
            const last_ptr = self.getElementSparsePtr(self.dense_keys.getLast());
            // 1. set 'data' in dense array to be the value of the last element in the dense array
            const dense_index = p.keys[getPageOffset(data)];
            last_ptr.* = dense_index;
            // 2. set 'data' in the sparse array to set to Null
            p.keys[getPageOffset(data)] = Null;

            _ = self.dense_keys.swapRemove(dense_index);
            _ = self.dense_data.swapRemove(dense_index);
            return dense_index;
        }

        pub inline fn get(self: *@This(), key: K) *V {
            const dense_index = self.getDenseIndex(key);
            return &self.dense_data[dense_index];
        }

        pub fn keys(self: *@This()) []K {
            return self.dense_keys.items;
        }
        pub fn values(self: *@This()) []K {
            return self.dense_data.items;
        }
    };
}

test "sparseset init" {
    var _u1 = DisjointSparseSet(.{ .T = u1 }).init(std.testing.allocator);
    try std.testing.expectEqual(0, _u1.len());
}

test "u2 sparseset contains" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try std.testing.expect(!_u2.contains(0));
    try std.testing.expect(!_u2.contains(1));
}

test "u2 sparseset add" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try std.testing.expect(_u2.contains(0));
    try std.testing.expectEqual(1, _u2.len());
}

test "u2 sparseset multiple add" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
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
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
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
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
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
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
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
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
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
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try std.testing.expect(!_u40.contains(0));
    try std.testing.expect(!_u40.contains(1));
}

test "u40 sparseset add" {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try std.testing.expect(_u40.contains(0));
    try std.testing.expectEqual(1, _u40.len());
}

test "u40 sparseset multiple add" {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
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
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
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
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
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
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
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
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
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

test DisjointSparseSet {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(32);
    try _u40.add(64);

    try std.testing.expectEqual(3, _u40.len());
    try std.testing.expect(_u40.contains(64));
    try std.testing.expect(_u40.contains(32));
    try std.testing.expect(_u40.contains(0));
}
