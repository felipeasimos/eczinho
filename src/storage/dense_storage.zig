const std = @import("std");
pub const chunks = @import("chunks/chunks.zig");
pub const tables = @import("tables/tables.zig");
pub const sparsesets = @import("sparseset/sparsesets.zig");
const DenseStorageType = @import("storage_types.zig").DenseStorageType;

pub const DenseStorageConfig = union(DenseStorageType) {
    Chunks: chunks.ChunksConfig,
    Tables: tables.TablesConfig,
};

pub const DenseStorageOptions = struct {
    World: type,
    Config: DenseStorageConfig,
};

pub fn DenseStorageFactory(options: DenseStorageOptions) type {
    return switch (options.Config) {
        .Chunks => |c| chunks.ChunksFactory(.{
            .Entity = options.World.Entity,
            .Components = options.World.Components,
            .Config = c,
        }),
        .Tables => |t| tables.TablesFactory(.{
            .Entity = options.World.Entity,
            .Components = options.World.Components,
            .Config = t,
        }),
    };
}

pub fn DenseStorageUnitFactory(options: DenseStorageOptions) type {
    return switch (options.Config) {
        .Chunks => |c| chunks.ChunksFactory(c).Chunk,
        .Tables => |t| tables.TablesFactory(t),
    };
}

pub fn DenseStorageStore(options: DenseStorageOptions) type {
    return struct {
        const Components = options.World.Components;
        const DenseStorage = DenseStorageFactory(options);
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
        pub fn getStorage(self: *@This(), dense_signature: Components) *DenseStorage {
            std.debug.assert(!dense_signature.hasIntersection(Components.SparseStorageMask));
            return self.storages.get(dense_signature).?;
        }
        pub fn tryGetStorage(self: *@This(), allocator: std.mem.Allocator, dense_signature: Components) !*DenseStorage {
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
    };
}
