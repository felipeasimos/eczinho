pub const chunks = @import("chunks.zig");
pub const sparseset = @import("sparseset.zig");
const std = @import("std");

pub const StorageType = enum {
    Chunks,
    SparseSet,
};

pub const StorageConfig = union(StorageType) {
    chunks: chunks.ChunkOptions,
    sparseset: sparseset.SparseSetOptions,
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
        pub const ReserveResult = @FieldType(@This(), "storage").ReserveResult;

        world: *World,
        storage: switch (options.Config) {
            .chunks => |c| chunks.ChunksFactory(c),
            .sparseset => |s| sparseset.SparseSet(s),
        },

        pub fn init(alloc: std.mem.Allocator, world: *World, signature: Components) !@This() {
            return .{
                .world = world,
                .storage = @FieldType(@This(), "storage").init(alloc, signature),
            };
        }
        pub fn get(self: *@This(), comptime Component: type, entt: Entity, location: *EntityLocation) *Component {
            return self.data.get(Component, entt, location);
        }
        pub fn getConst(self: *const @This(), comptime Component: type, entt: Entity, location: *EntityLocation) Component {
            return self.data.getConst(Component, entt, location);
        }
        pub fn reserve(self: *@This(), entt: Entity) !ReserveResult {
            return self.data.reserve(entt);
        }
        pub fn remove(self: *@This(), entt: Entity) !?struct { Entity, usize } {
            return self.data.remove(entt);
        }
    };
}
