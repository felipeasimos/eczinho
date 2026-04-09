const std = @import("std");
const entity = @import("../entity/entity.zig");
const components = @import("../components.zig");
const Tick = @import("../types.zig").Tick;
const WorldFactory = @import("../world.zig").World;
const dense_storage = @import("../storage/dense_storage.zig");

pub const ArchetypeOptions = struct {
    Components: type,
    Entity: type,
    DenseStorageConfig: dense_storage.DenseStorageConfig,
};

/// use ArchetypeOptions as options
pub fn Archetype(comptime options: ArchetypeOptions) type {
    return struct {
        const Self = @This();
        pub const ComponentTypeId = options.Components.ComponentTypeId;
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const DenseStorageConfig = options.DenseStorageConfig;
        pub const World = WorldFactory(.{
            .Components = Components,
            .Entity = Entity,
            .DenseStorageConfig = DenseStorageConfig,
        });
        pub const EntityLocation = World.EntityLocation;
        pub const DenseStorage = dense_storage.DenseStorageFactory(.{
            .World = World,
            .Config = options.DenseStorageConfig,
        });
        const StorageAddress = DenseStorage.StorageAddress;

        /// only contains components that both belong to this archetype AND have dense storage set
        signature: Components,
        storage: *DenseStorage,
        entities: std.ArrayList(Entity) = .empty,

        inline fn hash(tid_or_component: anytype) ComponentTypeId {
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                return tid_or_component;
            } else if (comptime Components.isComponent(tid_or_component)) {
                return Components.hash(tid_or_component);
            }
        }

        pub fn init(sig: Components, storage: *DenseStorage) !@This() {
            return .{
                .storage = storage,
                .signature = sig,
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.entities.deinit(allocator);
        }

        /// return the number of entities in the archetype
        pub inline fn len(self: *@This()) usize {
            return self.entities.items.len;
        }

        pub inline fn has(self: *@This(), tid_or_component: anytype) bool {
            return self.signature.has(tid_or_component);
        }

        /// add entity to archetype
        pub fn addEntity(self: *@This(), allocator: std.mem.Allocator, entt: Entity, location: *EntityLocation) !void {
            location.archetype_vec_index = self.entities.items.len;
            try self.entities.append(allocator, entt);
        }

        pub fn reserve(
            self: *@This(),
            allocator: std.mem.Allocator,
            entt: Entity,
        ) !DenseStorage.StorageAddress {
            return self.storage.reserve(allocator, entt);
        }

        pub const MoveToResult = struct {
            archetype_removal_result: struct { usize, usize },
            dense_removal_result: ?DenseStorage.RemovalResult,
        };

        fn moveStorageData(
            self: *@This(),
            allocator: std.mem.Allocator,
            entt: Entity,
            location: *EntityLocation,
            new_arch: *@This(),
            current_tick: Tick,
            removed_logs: anytype,
        ) !?DenseStorage.RemovalResult {
            const old_slot_index = location.dense_index;

            const old_dense_signature = self.signature.applyStorageTypeMask(.Dense);
            const new_dense_signature = new_arch.signature.applyStorageTypeMask(.Dense);

            // if there is no change in dense components, don't move data
            if (old_dense_signature.eql(new_dense_signature)) {
                std.debug.assert(new_arch.storage == self.storage);
                return null;
            }
            std.debug.assert(new_arch.storage != self.storage);

            const new_storage, const new_slot_index = try new_arch.reserve(allocator, entt);

            const old_storage = location.storage;

            // both archetypes have the non empty component -> just copy it
            {
                var intersection = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyNonEmptyMask();
                var iter_intersection = intersection.iterator();
                while (iter_intersection.nextTypeId()) |tid| {
                    const old_addr = old_storage.getComponentWithTypeId(tid, old_slot_index);
                    const new_addr = new_storage.getComponentWithTypeId(tid, new_slot_index);
                    @memcpy(new_addr, old_addr);
                }
            }
            // removed components with removed metadata -> add to removed logs
            {
                var removed = old_dense_signature
                    .difference(new_dense_signature)
                    .applyRemovedMask();
                var iter_removed = removed.iterator();
                while (iter_removed.nextTypeId()) |tid| {
                    try removed_logs.addRemoved(allocator, tid, entt, current_tick);
                }
            }
            // already existing components with added metadata -> copy metadata
            {
                var existing_with_added = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyAddedMask();
                var iter = existing_with_added.iterator();
                while (iter.nextTypeId()) |tid| {
                    new_storage
                        .getAddedArray(tid)[new_slot_index] = old_storage
                        .getAddedArray(tid)[old_slot_index];
                }
            }
            // already existing non empty components with changed metadata -> copy metadata
            {
                var existing_with_changed = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyChangedMask();
                var iter = existing_with_changed.iterator();
                while (iter.nextTypeId()) |tid| {
                    new_storage
                        .getChangedArray(tid)[new_slot_index] = old_storage
                        .getChangedArray(tid)[old_slot_index];
                }
            }
            // newly added components with added metadata -> update metadata
            {
                var newly_added = new_dense_signature
                    .difference(old_dense_signature)
                    .applyAddedMask();
                var iter = newly_added.iterator();
                while (iter.nextTypeId()) |tid| {
                    new_storage.getAddedArray(tid)[new_slot_index] = current_tick;
                }
            }
            // newly added component with changed metadata -> update metadata
            {
                var newly_added = new_dense_signature
                    .difference(old_dense_signature)
                    .applyChangedMask();
                var iter = newly_added.iterator();
                while (iter.nextTypeId()) |tid| {
                    new_storage.getChangedArray(tid)[new_slot_index] = current_tick;
                }
            }
            const removed_result = try old_storage.remove(allocator, old_slot_index) orelse null;
            location.dense_index = new_slot_index;
            location.storage = new_storage;
            return removed_result;
        }
        /// move entity to new archetype.
        /// this function only copies the values from dense components that exist in both archetypes.
        /// dense components only present in 'new_arch' must be set after this call.
        /// no move happens if the only difference between the two archetypes is sparse components
        /// returns swapped entity index and its new slot index (because of the remove)
        pub fn moveTo(
            self: *@This(),
            allocator: std.mem.Allocator,
            entt: Entity,
            location: *EntityLocation,
            new_arch: *@This(),
            current_tick: Tick,
            removed_logs: anytype,
        ) !MoveToResult {
            const old_archetype_vec_index = location.archetype_vec_index;

            // move dense storage data (if any dense components should be moved)
            const removed_result = try self.moveStorageData(allocator, entt, location, new_arch, current_tick, removed_logs);

            // add entity to new archetype
            try new_arch.addEntity(allocator, entt, location);
            location.arch = new_arch;

            // remove entity from current archetype
            const archetype_swapped_entt = self.entities.getLast();
            _ = self.entities.swapRemove(old_archetype_vec_index);

            return MoveToResult{
                .archetype_removal_result = .{
                    archetype_swapped_entt.index,
                    old_archetype_vec_index,
                },
                .dense_removal_result = removed_result,
            };
        }

        pub fn iterator(self: *@This()) Iterator {
            return Iterator.init(self);
        }

        pub const Iterator = struct {
            entities: []Entity,
            pub fn init(arch: *Self) @This() {
                return .{
                    .entities = arch.entities.items,
                };
            }
            pub fn next(self: *@This()) ?Entity {
                if (self.entities.len == 0) return null;
                const ret = self.entities[0];
                self.entities = self.entities[1..];
                return ret;
            }
        };
    };
}

test Archetype {
    const typeA = u64;
    // const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };
    const Components = components.Components(&.{ typeA, typeC, typeD, typeE });
    const ArchetypeType = Archetype(.{
        .Entity = entity.EntityTypeFactory(.medium),
        .Components = Components,
    });
    var archetype = try ArchetypeType.init(std.testing.allocator, Components.init(&.{ typeA, typeC, typeE }));
    defer archetype.deinit();

    try std.testing.expect(archetype.has(typeA));
    // can't add this line! (typeB isn't a component, so we get a compile time error!)
    // try std.testing.expect(!archetype.has(typeB));
    try std.testing.expect(archetype.has(typeC));
    try std.testing.expect(!archetype.has(typeD));
    try std.testing.expect(archetype.has(typeE));
}
