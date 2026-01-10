const std = @import("std");

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

        sparse: std.ArrayList(options.T) = .empty,
        dense: std.ArrayList(options.T) = .empty,
        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.sparse.deinit(self.allocator);
            self.dense.deinit(self.allocator);
        }

        pub fn len(self: *@This()) usize {
            return self.dense.items.len;
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
            return toUsize(data) < self.sparse.items.len and
                self.sparse.items[toUsize(data)] != Null;
        }

        /// adds integer to set. Nothing happens if integer is already contained
        pub fn add(self: *@This(), data: options.T) !void {
            std.debug.assert(!self.contains(data));
            std.debug.assert(data != Null);
            // is not within sparse range
            if (!(toUsize(data) < self.sparse.items.len)) {
                // get difference between sparse size and element
                // append that many times to set dense index
                const diff = toUsize(data) - self.sparse.items.len + 1;
                try self.sparse.appendNTimes(self.allocator, Null, diff);
            }
            self.sparse.items[toUsize(data)] = toData(self.dense.items.len);
            try self.dense.append(self.allocator, data);
        }

        // remove integer from set. Nothing happens if integer is already not contained
        pub fn remove(self: *@This(), data: options.T) !void {
            std.debug.assert(self.contains(data));
            std.debug.assert(data != Null);

            // get dense index
            const dense_index = toUsize(self.sparse.items[toUsize(data)]);
            // nullify dense index
            self.sparse.items[toUsize(data)] = Null;

            // if this isn't the last item in the dense array, update the last item
            // index in the sparse array
            if (self.dense.getLastOrNull()) |last_sparse_index| {
                if (dense_index + 1 != self.dense.items.len) {
                    self.sparse.items[toUsize(last_sparse_index)] = toData(dense_index);
                }
            }
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
