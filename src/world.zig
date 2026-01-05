const std = @import("std");
const entity = @import("entity.zig");

pub const WorldOptions = struct {
    ComponentTypes: []type = .{},
    Entity: type = entity.EntityClass(.medium),
    // Systems: []type = .{},
    // archetype_chunk_size: u8 = 128,
};

pub fn World(comptime options: WorldOptions) type {
    return struct {
        pub const ComponentTypes = options.ComponentTypes;
        pub const Entity = options.Entity;
        pub const ComponentBitSet = std.bit_set.StaticBitSet(ComponentTypes.len);
        pub const ArchetypePtr = *anyopaque;

        const EntityLocation = struct {
            archetype_ptr: ?*ArchetypePtr = null,
            version: options.Entity.VersionInt = 0,
        };

        allocator: std.mem.Allocator,
        components_to_archetypes: std.AutoHashMap(ComponentBitSet, ArchetypePtr),
        entities_to_locations: std.ArrayList(EntityLocation),
        free_entity_list: std.ArrayList(Entity),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .components_to_archetypes = @FieldType(@This(), "components_to_archetypes").init(allocator),
                .entities_to_locations = @FieldType(@This(), "entities_to_archetypes").empty,
                .free_entity_list = @FieldType(@This(), "free_entity_list").empty,
            };
        }

        fn componentId(comptime T: type) usize {
            if (std.mem.indexOfScalar(type, options.ComponentTypes, T)) |idx| {
                return idx;
            }
            @compileError("This type was not registered as a component");
        }

        fn isComponent(comptime T: type) bool {
            const idx = std.mem.indexOfScalar(type, options.ComponentTypes, T);
            return idx != null;
        }

        fn toBitset(comptime Types: []type) ComponentBitSet {
            var bitset = ComponentBitSet.initEmpty();
            for (Types) |Type| {
                const idx = componentId(Type);
                bitset.set(idx);
            }
            return bitset;
        }

        fn toComponentArray(comptime bitset: ComponentBitSet) [bitset.bit_length]type {
            var iter = bitset.iterator(.{});
            var components = .{};
            while (iter.next()) |idx| {
                components = components ++ .{options.ComponentTypes[idx]};
            }
            return components;
        }

        pub fn valid(self: *@This(), id: Entity) bool {
            if (id.version == 0) return false;
            if (id.index >= self.entities_to_locations.items.len) return false;
            return self.entities_to_locations.items[id.index].version == id.version;
        }

        pub fn create(self: *@This()) Entity {
            const new_entity = new_entity: {
                if (self.free_entity_list.pop()) |old_entity| {
                    break :new_entity old_entity;
                }
                break :new_entity Entity{
                    .index = self.entities_to_locations.items.len,
                    .version = 1,
                };
            };
            self.entities_to_locations.append(.{
                .archetype_ptr = null,
                .version = new_entity.version,
            });
            return new_entity;
        }

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
