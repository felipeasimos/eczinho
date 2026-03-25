pub const chunks = @import("chunks.zig");
pub const tables = @import("table/tables.zig");
pub const sparsesets = @import("sparseset/sparsesets.zig");
const std = @import("std");
const Tick = @import("../types.zig").Tick;
const DenseStorageType = @import("storage_types.zig").DenseStorageType;

pub const DenseStorageConfig = union(DenseStorageType) {
    Chunks: chunks.ChunksOptions,
    Tables: tables.TablesOptions,
};

pub const DenseStorageOptions = struct {
    World: type,
    Config: DenseStorageConfig,
};

pub fn DenseStorage(options: DenseStorageOptions) type {
    return struct {
        pub const World = options.World;
        pub const Entity = options.World.Entity;
        pub const EntityLocation = options.World.EntityLocation;
        pub const Components = options.World.Components;
        pub const StorageTypeSelected = switch (options.Config) {
            .Chunks => |c| chunks.ChunksFactory(c),
            .Tables => |t| tables.Tables(t),
        };
        pub const ReserveResult = StorageTypeSelected.ReserveResult;
        pub const Tables = StorageTypeSelected;
        // pub const Chunk = StorageTypeSelected.Chunk;
        pub const Iterator = StorageTypeSelected.Iterator;

        // world: *World,
        storage: StorageTypeSelected,

        pub fn init(alloc: std.mem.Allocator, signature: Components) !@This() {
            return .{
                // .world = world,
                .storage = try StorageTypeSelected.init(alloc, signature),
            };
        }
        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            self.storage.deinit(alloc);
        }
        pub fn get(self: *@This(), comptime Component: type, entt: Entity, location: *EntityLocation) *Component {
            return self.storage.get(Component, entt, location);
        }
        pub fn getConst(self: *const @This(), comptime Component: type, entt: Entity, location: *EntityLocation) Component {
            return self.storage.getConst(Component, entt, location);
        }
        pub fn reserve(self: *@This(), allocator: std.mem.Allocator, entt: Entity) !ReserveResult {
            return self.storage.reserve(allocator, entt);
        }
        pub fn remove(self: *@This(), entt: Entity) !?struct { Entity, usize } {
            return self.storage.remove(entt);
        }
        pub fn len(self: *@This()) usize {
            return self.storage.len();
        }
        pub fn getSignature(self: @This()) Components {
            return self.storage.signature;
        }
    };
}
