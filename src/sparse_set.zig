const std = @import("std");

pub fn SparseSet(comptime T: type) type {
    const data_bits = @typeInfo(T).int.bits;
    const usize_bits = @typeInfo(usize).int.bits;

    return struct {
        const Null = std.math.maxInt(T);

        sparse: std.ArrayList(T) = .empty,
        dense: std.ArrayList(T) = .empty,
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

        fn toUsize(data: T) usize {
            if (data_bits > usize_bits) {
                return @truncate(data);
            }
            return @intCast(data);
        }

        fn toData(idx: usize) T {
            if (data_bits > usize_bits) {
                return @intCast(idx);
            }
            return @truncate(idx);
        }

        /// check if set already contains integer
        pub fn contains(self: *@This(), data: T) bool {
            return toUsize(data) < self.sparse.items.len and
                self.sparse.items[toUsize(data)] != Null;
        }

        /// adds integer to set. Nothing happens if integer is already contained
        pub fn add(self: *@This(), data: T) !void {
            // is within sparse range
            if (toUsize(data) < self.sparse.items.len) {
                const contained = self.sparse.items[toUsize(data)] != Null;
                if (contained) {
                    return;
                }
                self.sparse.items[toUsize(data)] = toData(self.dense.items.len);
                try self.dense.append(self.allocator, data);
            } else {
                // get difference between sparse size and element
                // append that many times to set dense index
                const diff = toUsize(data) - self.sparse.items.len + 1;
                try self.sparse.appendNTimes(self.allocator, toData(diff), Null);
                self.sparse.items[toUsize(data)] = toData(self.dense.items.len);
            }
        }

        // remove integer from set. Nothing happens if integer is already not contained
        pub fn remove(self: *@This(), data: T) !void {
            // is within range
            if (toUsize(data) < self.sparse.items.len) {
                // get dense index
                const dense_index = self.sparse.items[toUsize(data)];
                const contained = dense_index != Null;
                if (!contained) {
                    return;
                }
                // nullify dense index
                self.sparse.items[toUsize(data)] = Null;

                // if this isn't the last item in the dense array, update the last item
                // index in the sparse array
                if (toUsize(dense_index) != self.dense.items.len - 1) {
                    const last_sparse_index = self.dense.getLast();
                    self.sparse.items[toUsize(last_sparse_index)] = toData(dense_index);
                }
                self.dense.swapRemove(toUsize(data));
            }
        }
    };
}

test SparseSet {
    var _u1 = SparseSet(u1).init(std.testing.allocator);
    defer _u1.deinit();

    try _u1.add(0);
    try std.testing.expect(_u1.contains(0));
    try std.testing.expect(!_u1.contains(1));

    var _u64 = SparseSet(u64).init(std.testing.allocator);
    defer _u64.deinit();

    try _u64.add(0);
    try std.testing.expect(_u64.contains(0));
    try std.testing.expect(!_u64.contains(1));
}
