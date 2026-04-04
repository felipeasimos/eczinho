const std = @import("std");

pub const EntityRegistryOptions = struct {
    EntityLocation: type,
    Archetype: type,
};

pub fn EntityRegistry(comptime options: EntityRegistryOptions) type {
    return struct {
        pub const Archetype = options.Archetype;
        pub const EntityLocation = options.EntityLocation;
        pub const Entity = Archetype.Entity;
        pub const Components = Archetype.Components;
        /// entity index to -> generations + archetype
        entities_to_locations: std.ArrayList(EntityLocation) = .empty,
        free_entity_list: std.ArrayList(Entity.Index) = .empty,

        pub fn init() @This() {
            return .{};
        }

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            self.free_entity_list.deinit(alloc);
            self.entities_to_locations.deinit(alloc);
        }

        pub inline fn getEntityLocation(self: *@This(), entt: Entity) *EntityLocation {
            return &self.entities_to_locations.items[entt.index];
        }

        pub inline fn setEntityDenseIndex(self: *@This(), entt_index: usize, dense_index: usize) void {
            self.entities_to_locations.items[entt_index].dense_index = dense_index;
        }

        pub inline fn setEntityArchetypeIndex(self: *@This(), entt_index: usize, archetype_index: usize) void {
            self.entities_to_locations.items[entt_index].archetype_vec_index = archetype_index;
        }

        pub inline fn valid(self: *@This(), entt: Entity) bool {
            if (entt.index >= self.entities_to_locations.items.len) return false;
            return self.entities_to_locations.items[entt.index].version == entt.version;
        }

        pub inline fn getEntityArchetype(self: *@This(), entt: Entity) *Archetype {
            std.debug.assert(self.valid(entt));
            return self.entities_to_locations.items[entt.index].arch;
        }

        pub inline fn getEntitySignature(self: *@This(), entt: Entity) Components {
            return self.getEntityArchetype(entt).signature;
        }

        /// Create a new entity and return it
        pub fn create(self: *@This(), allocator: std.mem.Allocator, empty_arch: *Archetype) !Entity {
            const entity_id = new_entity: {
                // use previously deleted entity index (if there is any)
                if (self.free_entity_list.pop()) |old_index| {
                    const version = self.entities_to_locations.items[@intCast(old_index)].version;
                    break :new_entity Entity{
                        .index = old_index,
                        .version = version,
                    };
                }
                // create brand new entity index
                const new_index: Entity.Index = @intCast(self.entities_to_locations.items.len);
                // SAFETY: will be set afterwards using the entity index
                try self.entities_to_locations.append(allocator, undefined);
                break :new_entity Entity{
                    .index = new_index,
                    .version = 0,
                };
            };
            // SAFETY: set right afterwards
            var location_ptr: *EntityLocation = &self.entities_to_locations.items[@intCast(entity_id.index)];
            try empty_arch.addEntity(allocator, entity_id, location_ptr);
            const storage, const slot_index = try empty_arch.reserve(allocator, entity_id);
            location_ptr.arch = empty_arch;
            location_ptr.version = entity_id.version;
            location_ptr.storage = storage;
            location_ptr.dense_index = slot_index;

            return entity_id;
        }

        pub fn destroy(self: *@This(), alloc: std.mem.Allocator, entt: Entity) !void {
            std.debug.assert(self.valid(entt));
            try self.free_entity_list.append(alloc, entt.index);
            self.entities_to_locations.items[entt.index].version += 1;
        }
    };
}
