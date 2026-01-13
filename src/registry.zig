const std = @import("std");
const entity = @import("entity.zig");
const type_id = @import("type_id.zig");
const ComponentsFactory = @import("components.zig").Components;

pub const RegistryOptions = struct {
    ComponentTypes: []type,
    Entity: type = entity.EntityTypeFactory(.medium),
};

pub fn Registry(comptime options: RegistryOptions) type {
    return struct {
        pub const ComponentTypes = options.ComponentTypes;
        pub const Entity = options.Entity;
        pub const Components = ComponentsFactory(ComponentTypes);
        pub const ComponentBitSet = Components.BitSet;
        pub const ArchetypePtr = *anyopaque;

        const EntityLocation = struct {
            archetype_ptr: ?*ArchetypePtr = null,
            // current (if alive) or next (if dead) generation of an entity index.
            version: options.Entity.Version = 0,
        };

        allocator: std.mem.Allocator,
        components_to_archetypes: std.AutoHashMap(ComponentBitSet, ArchetypePtr),
        /// entity index to -> generations + archetype
        entities_to_locations: std.ArrayList(EntityLocation),
        free_entity_list: std.ArrayList(Entity.Index),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .components_to_archetypes = @FieldType(@This(), "components_to_archetypes").init(allocator),
                .entities_to_locations = @FieldType(@This(), "entities_to_locations").empty,
                .free_entity_list = @FieldType(@This(), "free_entity_list").empty,
            };
        }

        pub fn valid(self: *@This(), id: Entity) bool {
            if (id.index >= self.entities_to_locations.items.len) return false;
            return self.entities_to_locations.items[id.index].version == id.version;
        }

        /// Create a new entity and return it
        pub fn create(self: *@This()) Entity {
            const entity_index = new_entity: {
                // use previously deleted entity index (if there is any)
                if (self.free_entity_list.pop()) |old_index| {
                    const version = self.entities_to_locations.items[@intCast(old_index)].version;
                    break :new_entity Entity{
                        .index = old_index,
                        .version = version,
                    };
                }
                // create brand new entity index
                break :new_entity Entity{
                    .index = self.entities_to_locations.items.len,
                };
            };
            // update entity_to_locations with new id
            self.entities_to_locations.append(self.allocator, .{
                .archetype_ptr = null,
                .version = entity_index.version,
            });
            return entity_index;
        }

        /// Destroy an entity
        pub fn destroy(self: *@This(), id: Entity) void {
            std.debug.assert(self.valid(id));

            self.free_entity_list.append(id);
            self.entities_to_locations.items[id.index].version += 1;
        }

        // pub fn add(self: *@This(), id: Entity, component: anytype) void {
        //     std.debug.assert(self.valid(id));
        //
        // }
        //
        // pub fn remove(self: *@This(), id: Entity, ComponentType: T) void {
        //     std.debug.assert(self.valid(id));
        //
        // }
        //
        // pub fn get(self: *@This(), id: Entity, ComponentType: T) *T {
        //     std.debug.assert(self.valid(id));
        //
        // }
        //
        // pub fn has(self: *@This(), id: Entity, ComponentType: T) void {
        //     std.debug.assert(self.valid(id));
        //
        // }
        //
        // pub fn forEach(self: *@This(), comptime ComponentTypes: []type, func: anytype) void {
        // }
    };
}

test RegistryOptions {
    _ = @import("type_id.zig");
    _ = @import("sparse_set.zig");
    _ = @import("archetype.zig");
}
