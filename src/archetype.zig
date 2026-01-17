const std = @import("std");
const sparseset = @import("sparse_set.zig");
const entity = @import("entity.zig");
const components = @import("components.zig");
const array = @import("array.zig");

pub const ArchetypeOptions = struct {
    ComponentBitSet: type,
    EntityType: type,
};

/// use ArchetypeOptions as options
pub fn Archetype(comptime options: ArchetypeOptions) type {
    return struct {
        const ComponentTypeId = options.ComponentBitSet.ComponentTypeId;
        const ComponentBitSet = options.ComponentBitSet;
        const Entity = options.EntityType;
        const TypeErasedArchetype = Archetype(.{
            .ComponentBitSet = options.ComponentBitSet,
            .EntityType = Entity,
        });
        signature: options.ComponentBitSet,
        components: std.AutoHashMap(ComponentTypeId, array.Array),
        entities_to_component_index: sparseset.SparseSet(.{
            .T = options.EntityType.Int,
            .PageMask = options.EntityType.entity_mask,
        }),
        allocator: std.mem.Allocator,

        inline fn hash(tid_or_component: anytype) ComponentTypeId {
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                return tid_or_component;
            } else if (comptime ComponentBitSet.isComponent(tid_or_component)) {
                return ComponentBitSet.hash(tid_or_component);
            }
        }

        /// creates the array if it doesn't exist. Uses type.
        inline fn tryGetComponentArray(self: *@This(), tid_or_component: anytype) !*array.Array {
            ComponentBitSet.checkSize(tid_or_component);
            const component_size = ComponentBitSet.getSize(tid_or_component);
            const component_alignment = ComponentBitSet.getAlignment(tid_or_component);
            const new_array = array.Array.init(component_size, component_alignment);
            const entry = try self.components.getOrPutValue(hash(tid_or_component), new_array);
            return entry.value_ptr;
        }

        /// returns null if the array doesn't exist. Uses type
        inline fn optGetComponentArray(self: *@This(), tid_or_component: anytype) ?*array.Array {
            ComponentBitSet.checkSize(tid_or_component);
            if (self.components.getEntry(hash(tid_or_component))) |entry| {
                return entry.value_ptr;
            }
            return null;
        }

        /// returns the array assuming that it exists. Uses type
        inline fn getComponentArray(self: *@This(), tid_or_component: anytype) *array.Array {
            ComponentBitSet.checkSize(tid_or_component);
            return self.components.getEntry(hash(tid_or_component)).?.value_ptr;
        }

        pub fn init(alloc: std.mem.Allocator, sig: options.ComponentBitSet) @This() {
            return .{
                .signature = sig,
                .components = @FieldType(@This(), "components").init(alloc),
                .entities_to_component_index = @FieldType(@This(), "entities_to_component_index").init(alloc),
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            var iter = self.signature.iterator();
            while (iter.nextTypeIdNonEmpty()) |tid| {
                if (self.optGetComponentArray(tid)) |arr| {
                    arr.deinit(self.allocator);
                }
            }
            self.components.deinit();
            self.entities_to_component_index.deinit();
        }

        pub inline fn len(self: *@This()) usize {
            return self.entities_to_component_index.len();
        }

        pub inline fn has(self: *@This(), tid_or_component: anytype) bool {
            return self.signature.has(tid_or_component);
        }

        pub inline fn entities(self: *@This()) []Entity {
            return self.entities_to_component_index.items();
        }

        inline fn getEntityComponentIndex(self: *@This(), entt: Entity) usize {
            return self.entities_to_component_index.getDenseIndex(entt.toInt());
        }

        pub fn get(self: *@This(), comptime Component: type, entt: Entity) *Component {
            ComponentBitSet.checkSize(Component);
            std.debug.assert(self.has(Component));
            std.debug.assert(self.valid(entt));

            const entt_index = self.entities_to_component_index.getDenseIndex(entt.toInt());
            const component_arr = self.getComponentArray(Component);
            return component_arr.getAs(Component, entt_index);
        }

        pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {
            ComponentBitSet.checkSize(Component);
            std.debug.assert(self.has(Component));
            std.debug.assert(self.valid(entt));

            const entt_index = self.entities_to_component_index.getDenseIndex(entt.toInt());
            const component_arr = self.getComponentArray(Component);
            return component_arr.getConst(Component, entt_index);
        }

        pub fn valid(self: *@This(), entt: options.EntityType) bool {
            return self.entities_to_component_index.contains(entt.toInt());
        }

        pub fn reserve(self: *@This(), entt: options.EntityType) !void {
            std.debug.assert(!self.valid(entt));

            var iter = self.signature.iterator();
            while (iter.nextTypeIdNonEmpty()) |tid| {
                const component_arr = try self.tryGetComponentArray(tid);
                try component_arr.reserve(self.allocator, 1);
            }
            try self.entities_to_component_index.add(entt.toInt());
        }

        /// add entities with its component values to this archetype.
        /// zero sized components must not be passed.
        /// ignored component will be undefined.
        pub fn add(self: *@This(), entt: options.EntityType, values: anytype) !void {
            std.debug.assert(!self.valid(entt));

            inline for (values) |value| {
                ComponentBitSet.checkSize(@TypeOf(value));
                const component_arr = try self.tryGetComponentArray(@TypeOf(value));
                try component_arr.append(self.allocator, value);
            }
            try self.entities_to_component_index.add(entt.toInt());
        }

        pub fn remove(self: *@This(), entt: Entity) void {
            std.debug.assert(self.valid(entt));

            const entt_index = self.entities_to_component_index.remove(entt.toInt());
            var iter = self.signature.iterator();
            while (iter.nextTypeIdNonEmpty()) |tid| {
                if (self.optGetComponentArray(tid)) |arr| {
                    _ = arr.swapRemove(entt_index);
                }
            }
        }

        /// move entity to new archetype.
        /// this function only copies the values from component that exist in both archetypes.
        /// components only present in 'new_arch' must be set after this call.
        pub fn moveTo(self: *@This(), entt: Entity, new_arch: *TypeErasedArchetype) !void {
            std.debug.assert(self.valid(entt));
            std.debug.assert(!new_arch.valid(entt));

            const entt_index = self.getEntityComponentIndex(entt);
            try new_arch.reserve(entt);
            var iter_type_id = self.signature.iterator();
            while (iter_type_id.nextTypeIdNonEmpty()) |tid| {
                if (new_arch.signature.has(tid)) {
                    const old_addr = self.getComponentArray(tid).get(entt_index);
                    const new_addr = new_arch.getComponentArray(tid).get(entt_index);
                    @memcpy(new_addr, old_addr);
                }
            }
            self.remove(entt);
        }
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
        .EntityType = entity.EntityTypeFactory(.medium),
        .ComponentBitSet = Components,
    });
    var archetype = ArchetypeType.init(std.testing.allocator, Components.init(&.{ typeA, typeC, typeE }));
    defer archetype.deinit();

    try std.testing.expect(archetype.has(typeA));
    // can't add this line! (typeB isn't a component, so we get a compile time error!)
    // try std.testing.expect(!archetype.has(typeB));
    try std.testing.expect(archetype.has(typeC));
    try std.testing.expect(!archetype.has(typeD));
    try std.testing.expect(archetype.has(typeE));

    var values = .{ @as(typeA, 4), typeE{ .a = 23, .b = 342 } };
    const entt_id = entity.EntityTypeFactory(.medium){ .index = 1, .version = 0 };
    try archetype.add(entt_id, &values);
    try std.testing.expect(archetype.valid(entt_id));
    try std.testing.expectEqual(@as(typeA, 4), archetype.getConst(typeA, entt_id));
    try std.testing.expectEqual(@as(typeE, .{ .a = 23, .b = 342 }), archetype.getConst(typeE, entt_id));
    archetype.remove(entt_id);
    try std.testing.expect(!archetype.valid(entt_id));
}
