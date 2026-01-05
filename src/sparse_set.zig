const std = @import("std");

pub fn EntitySparseSet(comptime EntityType: type) type {
    return struct {
        const page_size: usize = std.heap.pageSize();
        const Null = std.math.maxInt(EntityType.IndexInt);

        sparse: std.ArrayList([page_size]EntityType.IndexInt),
        dense: std.ArrayList(EntityType),

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .sparse = .empty,
                .dense = .empty,
                .allocator = allocator,
            };
        }

        pub fn get(self: *@This(), id: EntityType.IndexInt) *EntityType {
            if (id >= self.sparse.items.len) {
                return Null;
            }
            const dense_idx = self.sparse.items[id];
            return &self.dense.items[dense_idx];
        }

        pub fn getOrC

        pub fn remove(self: *@This(), id: EntityType.IndexInt) EntityType.IndexInt {
            if (id >= self.sparse.items.len) {
                return Null;
            }
            const to_remove_dense_idx = self.sparse.items[id];
            const last_dense_idx = self.dense.items.len - 1;
            const last_dense = self.dense.items[last_dense_idx];
            self.dense.items[to_remove_dense_idx] = last_dense;
            self.sparse.items[self.dense.items[last_dense_idx]] = to_remove_dense_idx;
            self.sparse.items[id] = Null;
            _ = self.dense.pop();
        }
    };
}

