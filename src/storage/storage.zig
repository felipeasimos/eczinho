pub const chunks = @import("chunks.zig");
pub const sparseset = @import("sparseset.zig");
const std = @import("std");

pub const StorageType = enum {
    Dense,
    Sparse,
};

pub const StorageConfig = union(StorageType) {
    Dense: chunks.ChunkOptions,
    Sparse: sparseset.SparseSetOptions,
};

pub const StorageOptions = struct {
    World: type,
    Config: StorageConfig,
};

pub fn Storage(options: StorageOptions) type {
    return struct {
        pub const World = options.World;
        pub const Entity = options.World.Entity;
        pub const EntityLocation = options.World.EntityLocation;
        pub const Components = options.World.Components;
        pub const StorageTypeSelected = switch (options.Config) {
            .Dense => |c| chunks.ChunksFactory(c),
            .Sparse => |s| sparseset.SparseSet(s),
        };
        pub const ReserveResult = StorageTypeSelected.ReserveResult;
        pub const Chunk = StorageTypeSelected.Chunk;
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
    };
}
