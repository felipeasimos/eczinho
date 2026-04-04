const std = @import("std");
const dense_storage = @import("dense_storage.zig");

pub fn DenseStorageStore(options: dense_storage.DenseStorageOptions) type {
    return struct {
        const Components = options.World.Components;
        const Entity = options.World.Entity;
        const DenseStorage = dense_storage.DenseStorageFactory(options);
        const Self = @This();
        storages: std.AutoHashMap(Components, *DenseStorage),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .storages = @FieldType(@This(), "storages").init(allocator),
            };
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            var iter = self.storages.valueIterator();
            while (iter.next()) |storage| {
                const storage_ptr = storage.*;
                storage_ptr.deinit(allocator);
                allocator.destroy(storage_ptr);
            }
            self.storages.deinit();
        }
        pub fn createStorageSignatureList(self: *@This(), allocator: std.mem.Allocator, comptime MustHave: []const type, comptime CannotHave: []const type) !std.ArrayList(Components) {
            const must_have_components = comptime Components.init(MustHave);
            const cannot_have_components = comptime Components.init(CannotHave);

            var key_iter = self.storages.keyIterator();
            var arr: std.ArrayList(Components) = .empty;
            while (key_iter.next()) |key| {
                const sig = key.*;
                if (must_have_components.isSubsetOf(sig) and !cannot_have_components.hasIntersection(sig)) {
                    try arr.append(allocator, sig);
                }
            }
            return arr;
        }

        pub fn getStorageFromSignature(self: *@This(), dense_signature: Components) *DenseStorage {
            std.debug.assert(!dense_signature.hasIntersection(Components.SparseStorageMask));
            return self.storages.get(dense_signature).?;
        }
        pub fn tryGetStorageFromSignature(self: *@This(), allocator: std.mem.Allocator, dense_signature: Components) !*DenseStorage {
            std.debug.assert(!dense_signature.hasIntersection(Components.SparseStorageMask));
            const entry = try self.storages.getOrPut(dense_signature);
            if (entry.found_existing) {
                return entry.value_ptr.*;
            }
            const storage_ptr = try allocator.create(DenseStorage);
            storage_ptr.* = try DenseStorage.init(allocator, dense_signature);
            entry.value_ptr.* = storage_ptr;
            return storage_ptr;
        }
        pub fn iterator(self: *@This()) @FieldType(@This(), "storages").ValueIterator {
            return self.storages.valueIterator();
        }
    };
}
