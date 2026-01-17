const std = @import("std");
const entity = @import("entity.zig");
const ComponentsFactory = @import("components.zig").Components;
const archetype = @import("archetype.zig");
const query = @import("query/query.zig");

pub const RegistryOptions = struct {
    ComponentTypes: []const type,
    Entity: type = entity.EntityTypeFactory(.medium),
};

pub fn Registry(comptime options: RegistryOptions) type {
    return struct {
        pub const ComponentTypes = options.ComponentTypes;
        pub const Entity = options.Entity;
        pub const ComponentBitSet = ComponentsFactory(ComponentTypes);
        pub const Archetype = archetype.Archetype(.{
            .EntityType = Entity,
            .ComponentBitSet = ComponentBitSet,
        });

        const EntityLocation = struct {
            signature: ?ComponentBitSet = null,
            // current (if alive) or next (if dead) generation of an entity index.
            version: options.Entity.Version = 0,
        };

        allocator: std.mem.Allocator,
        archetypes: std.AutoHashMap(ComponentBitSet, Archetype),
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

        fn getEntityArchetype(self: *@This(), entt: Entity) *Archetype {
            std.debug.assert(self.valid(entt));
            const signature = self.entities_to_locations.items[entt.index].signature.?;
            return self.archetypes.getPtr(signature).?;
        }

        fn getArchetypeFromSignature(self: *@This(), signature: ComponentBitSet) !*Archetype {
            const entry = try self.archetypes.getOrPut(signature);
            if (entry.found_existing) {
                return @ptrCast(entry.value_ptr);
            }
            entry.value_ptr.* = Archetype.init(self.allocator, signature);
            return entry.value_ptr;
        }

        pub fn valid(self: *@This(), id: Entity) bool {
            if (id.index >= self.entities_to_locations.items.len) return false;
            return self.entities_to_locations.items[id.index].version == id.version;
        }

        /// Create a new entity and return it
        pub fn create(self: *@This()) Entity {
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
                break :new_entity Entity{
                    .index = @intCast(self.entities_to_locations.items.len),
                    .version = 0,
                };
            };
            // update entity_to_locations with new id
            const empty_arch = self.getArchetypeFromSignature(ComponentBitSet.init(&.{})) catch unreachable;
            self.entities_to_locations.append(self.allocator, .{
                .signature = empty_arch.signature,
                .version = entity_id.version,
            }) catch unreachable;
            empty_arch.reserve(entity_id) catch unreachable;
            return entity_id;
        }

        pub fn has(self: *@This(), comptime Component: type, entt: Entity) bool {
            std.debug.assert(self.valid(entt));
            return self.getEntityArchetype(entt).has(Component);
        }

        pub fn remove(self: *@This(), comptime Component: type, entt: Entity) void {
            std.debug.assert(self.valid(entt));
            const old_arch = self.getEntityArchetype(entt);
            var new_signature = old_arch.signature;
            new_signature.remove(Component);
            const new_arch = self.getArchetypeFromSignature(new_signature) catch unreachable;
            old_arch.moveTo(
                entt,
                new_arch,
            ) catch unreachable;
            self.entities_to_locations.items[entt.index].signature = new_arch.signature;
        }

        pub fn add(self: *@This(), entt: Entity, value: anytype) void {
            std.debug.assert(self.valid(entt));
            const Component = @TypeOf(value);

            const old_arch = self.getEntityArchetype(entt);

            var new_signature = old_arch.signature;
            new_signature.add(Component);

            const new_arch = self.getArchetypeFromSignature(new_signature) catch unreachable;
            old_arch.moveTo(
                entt,
                new_arch,
            ) catch unreachable;
            self.entities_to_locations.items[entt.index].signature = new_arch.signature;
            // add new component value
            new_arch.get(Component, entt).* = value;
        }

        pub fn get(self: *@This(), comptime Component: type, entt: Entity) *Component {
            std.debug.assert(self.valid(entt));
            return self.getEntityArchetype(entt).get(Component, entt);
        }

        pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {
            std.debug.assert(self.valid(entt));
            return self.getEntityArchetype(entt).getConst(Component, entt);
        }

        /// use in systems to obtain a query. System signature should be like:
        /// fn systemExample(q: Query(.{.q = &.{typeA, *typeB}, .with = &.{typeC}}) !void {
        ///     ...
        /// }
        /// checkout QueryRequest for more information
        pub fn Query(comptime req: query.Request) type {
            return query.Factory(.{
                .request = req,
                .EntityType = Entity,
                .ComponentBitSet = ComponentBitSet,
            });
        }
    };
}

test "all" {
    _ = @import("sparse_set.zig");
    _ = @import("archetype.zig");
    _ = @import("array.zig");
    _ = @import("components.zig");
    _ = @import("entity.zig");
}

test Registry {
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };

    var registry = Registry(.{
        .ComponentTypes = &.{ typeA, typeB, typeC, typeD, typeE },
        .Entity = entity.EntityTypeFactory(.medium),
    }).init(std.testing.allocator);
    defer registry.deinit();

    const entt_id = registry.create();
    registry.add(entt_id, typeE{ .a = 1, .b = 2 });

    try std.testing.expect(registry.has(typeE, entt_id));
    try std.testing.expect(!registry.has(typeD, entt_id));

    try std.testing.expectEqual(1, registry.get(typeE, entt_id).a);
    try std.testing.expectEqual(2, registry.get(typeE, entt_id).b);

    try std.testing.expectEqual(1, registry.getConst(typeE, entt_id).a);
    try std.testing.expectEqual(2, registry.getConst(typeE, entt_id).b);
}

test "registry initialization test" {
    var registry = Registry(.{
        .ComponentTypes = &.{ u64, bool, struct {} },
        .Entity = entity.EntityTypeFactory(.small),
    }).init(std.testing.allocator);
    defer registry.deinit();
}

test "registry remove test" {
    var registry = Registry(.{
        .ComponentTypes = &.{ u64, bool, struct {} },
        .Entity = entity.EntityTypeFactory(.small),
    }).init(std.testing.allocator);
    const entt_id = registry.create();
    registry.add(entt_id, @as(u64, 7));
    registry.remove(u64, entt_id);
    defer registry.deinit();
}

test "query" {
    const camelCase1 = u31;
    const camelCase2 = u32;
    const camelCase3 = u33;
    const camelCase4 = u34;
    const camelCase5 = u35;
    const PascalCase1 = u36;
    const PascalCase2 = u37;
    const PascalCase3 = u38;
    const PascalCase4 = u39;
    const PascalCase5 = u40;
    const Reg = Registry(.{
        .ComponentTypes = &.{
            camelCase1,
            camelCase2,
            camelCase3,
            camelCase4,
            camelCase5,
            PascalCase1,
            PascalCase2,
            PascalCase3,
            PascalCase4,
            PascalCase5,
        },
    });
    const q: Reg.Query(.{
        .q = &.{
            camelCase1,
            *camelCase2,
            ?*camelCase3,
            *const camelCase4,
            ?*const camelCase5,
            PascalCase1,
            *PascalCase2,
            ?*PascalCase3,
            *const PascalCase4,
            ?*const PascalCase5,
        },
        .with = &.{ u32, f32 },
        .without = &.{u41},
    }) = undefined;
    try std.testing.expectEqual(u31, @FieldType(@TypeOf(q), "0"));
    try std.testing.expectEqual(*u32, @FieldType(@TypeOf(q), "1"));
    try std.testing.expectEqual(?*u33, @FieldType(@TypeOf(q), "2"));
    try std.testing.expectEqual(*const u34, @FieldType(@TypeOf(q), "3"));
    try std.testing.expectEqual(?*const u35, @FieldType(@TypeOf(q), "4"));

    try std.testing.expectEqual(u36, @FieldType(@TypeOf(q), "5"));
    try std.testing.expectEqual(*u37, @FieldType(@TypeOf(q), "6"));
    try std.testing.expectEqual(?*u38, @FieldType(@TypeOf(q), "7"));
    try std.testing.expectEqual(*const u39, @FieldType(@TypeOf(q), "8"));
    try std.testing.expectEqual(?*const u40, @FieldType(@TypeOf(q), "9"));
}
