const std = @import("std");
const entity = @import("entity.zig");
const type_id = @import("type_id.zig");
const ComponentsFactory = @import("components.zig").Components;
const archetype = @import("archetype.zig");

pub const RegistryOptions = struct {
    ComponentTypes: []const type,
    Entity: type = entity.EntityTypeFactory(.medium),
};

pub fn Registry(comptime options: RegistryOptions) type {
    return struct {
        pub const ComponentTypes = options.ComponentTypes;
        pub const Entity = options.Entity;
        pub const ComponentBitSet = ComponentsFactory(ComponentTypes);
        pub const TypeErasedArchetype = getArchetypeType(&.{});
        pub const ArchetypePtr = *TypeErasedArchetype;

        const EntityLocation = struct {
            archetype_ptr: ?ArchetypePtr = null,
            // current (if alive) or next (if dead) generation of an entity index.
            version: options.Entity.Version = 0,
        };

        allocator: std.mem.Allocator,
        archetypes: std.AutoHashMap(ComponentBitSet.BitSet, TypeErasedArchetype),
        /// entity index to -> generations + archetype
        entities_to_locations: std.ArrayList(EntityLocation),
        free_entity_list: std.ArrayList(Entity.Index),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .archetypes = @FieldType(@This(), "archetypes").init(allocator),
                .entities_to_locations = @FieldType(@This(), "entities_to_locations").empty,
                .free_entity_list = @FieldType(@This(), "free_entity_list").empty,
            };
        }

        pub fn deinit(self: *@This()) void {
            var iter = self.archetypes.valueIterator();
            while (iter.next()) |arch| {
                arch.deinit();
            }
            self.archetypes.deinit();
            self.entities_to_locations.deinit(self.allocator);
            self.free_entity_list.deinit(self.allocator);
        }

        fn getArchetypeType(comptime Signature: []const type) type {
            return archetype.Archetype(.{
                .EntityType = Entity,
                .Signature = Signature,
                .ComponentBitSet = ComponentBitSet,
            });
        }

        fn getEntityArchetype(self: *@This(), entt: Entity) ?*getArchetypeType(.{}) {
            std.debug.assert(self.valid(entity));
            if (self.entities_to_locations.items[entt.index].archetype_ptr) |archetype_ptr| {
                return @ptrCast(archetype_ptr);
            }
            return null;
        }

        fn castToTypedArchetype(ptr: *anyopaque, comptime Signature: []const type) *getArchetypeType(Signature) {
            return @ptrCast(@alignCast(ptr));
        }

        fn getArchetypeFromSignature(self: *@This(), comptime Signature: []const type) !*getArchetypeType(Signature) {
            const ArchetypeType = getArchetypeType(Signature);
            const entry = try self.archetypes.getOrPut(ComponentBitSet.comptimeBitSet(Signature));
            if (entry.found_existing) {
                return @ptrCast(entry.value_ptr);
            }
            entry.value_ptr.* = ArchetypeType.init(self.allocator);
            return castToTypedArchetype(entry.value_ptr, Signature);
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
                    .index = @intCast(self.entities_to_locations.items.len),
                    .version = 0,
                };
            };
            // update entity_to_locations with new id
            self.entities_to_locations.append(self.allocator, .{
                .archetype_ptr = self.getArchetypeFromSignature(&.{}) catch unreachable,
                .version = entity_index.version,
            }) catch unreachable;
            return entity_index;
        }

        // pub fn get(self: *@This(), comptime Component: type, entt: Entity) Component {
        //     std.debug.assert(self.valid(entt));
        //     const archetype_ptr = self.entities_to_locations.items[entt.index].archetype_ptr.?;
        //     archetype_ptr
        // }

        // add component to entity
        // pub fn add(self: *@This(), entt: Entity, value: anytype) void {
        //     std.debug.assert(self.valid(entt));
        // }

        // Destroy an entity
        // pub fn destroy(self: *@This(), id: Entity) void {
        //     std.debug.assert(self.valid(id));
        //
        //     self.free_entity_list.append(id);
        //     self.entities_to_locations.items[id.index].version += 1;
        // }

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

test "all" {
    _ = @import("type_id.zig");
    _ = @import("sparse_set.zig");
    _ = @import("archetype.zig");
}

test Registry {
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };
    var registry = Registry(.{
        .ComponentTypes = &[_]type{ typeA, typeB, typeC, typeD, typeE },
        .Entity = entity.EntityTypeFactory(.medium),
    }).init(std.testing.allocator);
    defer registry.deinit();
    _ = registry.create();
}
