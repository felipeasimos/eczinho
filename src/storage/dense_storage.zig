pub const chunks = @import("chunks.zig");
pub const tables = @import("tables.zig");
pub const sparsesets = @import("sparseset/sparsesets.zig");
const std = @import("std");
const Tick = @import("../types.zig").Tick;
const DenseStorageType = @import("storage_types.zig").DenseStorageType;

pub const DenseStorageConfig = union(DenseStorageType) {
    Chunks: chunks.ChunkOptions,
    Tables: tables.TableOptions,
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
        pub fn getSignature(self: @This()) Components {
            return self.storage.signature;
        }
        pub fn moveTo(
            from: *@This(),
            allocator: std.mem.Allocator,
            entt: Entity,
            to: *@This(),
            location: *EntityLocation,
            current_tick: Tick,
            removed_logs: anytype,
        ) !?struct { Entity, usize } {
            const new_storage, const new_index = try to.reserve(allocator);

            const old_index = location.dense_index;

            const old_storage = location.chunk;

            var old_iter_type_id = from.signature.iterator();
            while (old_iter_type_id.nextTypeId()) |tid| {
                // already existing component types
                if (to.getSignature().has(tid)) {
                    if (Components.getSize(tid) != 0) {
                        const old_type_index = old_storage.getNonEmptyTypeIndex(tid);
                        const old_addr = location
                            .chunk
                            .getElemWithTypeIndex(old_type_index, old_index);
                        const new_chunk_type_index = new_storage.getNonEmptyTypeIndex(tid);
                        const new_addr = new_storage.getElemWithTypeIndex(new_chunk_type_index, new_storage);
                        @memcpy(new_addr, old_addr);
                    }
                    // removed component types
                } else {
                    try removed_logs.addRemoved(tid, entt, current_tick);
                }
            }
            var new_iter_type_id = to.getSignature().iterator();
            while (new_iter_type_id.nextTypeId()) |tid| {
                const is_zst = Components.getSize(tid) == 0;
                // already existing component types
                if (from.signature.has(tid)) {
                    if (is_zst) {
                        const old_type_index = old_storage.getZSTIndex(tid);
                        const new_type_index = new_storage.getZSTIndex(tid);
                        new_storage
                            .getZSTMetadataArray(new_type_index)[new_storage] = old_storage
                            .getZSTMetadataArray(old_type_index)[old_index];
                    } else {
                        const old_type_index = old_storage.getNonEmptyTypeIndex(tid);
                        const new_type_index = new_storage.getNonEmptyTypeIndex(tid);
                        new_storage
                            .getNonEmptyMetadataArray(new_type_index, .Added)[new_index] = old_storage
                            .getNonEmptyMetadataArray(old_type_index, .Added)[old_index];
                        new_storage
                            .getNonEmptyMetadataArray(new_type_index, .Changed)[new_index] = old_storage
                            .getNonEmptyMetadataArray(old_type_index, .Changed)[old_index];
                    }
                    // newly added components types
                } else {
                    if (is_zst) {
                        const new_type_index = new_storage.getZSTIndex(tid);
                        new_storage.getZSTMetadataArray(new_type_index)[new_index] = current_tick;
                    } else {
                        const new_type_index = new_storage.getNonEmptyTypeIndex(tid);
                        new_storage.getNonEmptyMetadataArray(new_type_index, .Added)[new_index] = current_tick;
                        new_storage.getNonEmptyMetadataArray(new_type_index, .Changed)[new_index] = current_tick;
                    }
                }
            }
            const removed_result = old_storage.remove(allocator, old_index);
            switch (comptime options.Config) {
                .Dense => {
                    location.dense_index = @intCast(new_index);
                    location.chunk = new_storage;
                },
                .Sparse => location.dense_index = new_index,
            }
            location.arch = to;
            return removed_result;
        }
    };
}
