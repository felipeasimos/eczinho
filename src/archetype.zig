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

        /// creates the array if it doesn't exist. Uses type.
        fn tryGetComponentArray(self: *@This(), tid_or_component: anytype) !*array.Array {
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                const component_size = ComponentBitSet.getSize(tid_or_component);
                const entry = try self.components.getOrPutValue(tid_or_component, .init(component_size));
                return entry.value_ptr;
            } else if (comptime ComponentBitSet.isComponent(tid_or_component)) {
                const entry = try self.components.getOrPutValue(comptime ComponentBitSet.hash(tid_or_component), .init(@sizeOf(tid_or_component)));
                return entry.value_ptr;
            }
            @compileError("invalid type " ++ @typeName(@TypeOf(tid_or_component)) ++ ": must be a ComponentTypeId or a type in the component list");
        }

        /// returns null if the array doesn't exist. Uses type
        fn optGetComponentArray(self: *@This(), tid_or_component: anytype) ?*array.Array {
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                if (self.components.getEntry(tid_or_component)) |entry| {
                    return entry.value_ptr;
                }
                return null;
            } else if (comptime ComponentBitSet.isComponent(tid_or_component)) {
                if (self.components.getEntry(comptime ComponentBitSet.hash(tid_or_component))) |entry| {
                    return entry.value_ptr;
                }
                return null;
            }
            @compileError("invalid type " ++ @typeName(@TypeOf(tid_or_component)) ++ ": must be a ComponentTypeId or a type in the component list");
        }

        /// returns the array assuming that it exists. Uses type
        fn getComponentArray(self: *@This(), tid_or_component: anytype) *array.Array {
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                return self.components.getEntry(tid_or_component).?.value_ptr;
            } else if (comptime ComponentBitSet.isComponent(tid_or_component)) {
                return self.components.getEntry(comptime ComponentBitSet.hash(tid_or_component)).?.value_ptr;
            }
            @compileError("invalid type " ++ @typeName(@TypeOf(tid_or_component)) ++ ": must be a ComponentTypeId or a type in the component list");
        }

        fn canHaveArray(comptime Component: type) bool {
            return comptime @sizeOf(Component) != 0;
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

        pub fn len(self: *@This()) usize {
            return self.entities_to_component_index.len();
        }

        pub fn has(self: *@This(), tid_or_component: anytype) bool {
            return self.signature.has(tid_or_component);
        }

        pub fn entities(self: *@This()) []Entity {
            return self.entities_to_component_index.items();
        }

        fn getTypeId(self: *@This(), tid: ComponentTypeId, entt: Entity) []u8 {
            std.debug.assert(self.has(tid));
            std.debug.assert(self.contains(entt));

            const entt_index = self.entities_to_component_index.getDenseIndex(entt.toInt());
            const component_arr = self.tryGetComponentArray(tid) catch unreachable;
            return component_arr.get(entt_index);
        }

        pub fn get(self: *@This(), comptime Component: type, entt: Entity) *Component {
            if (comptime !canHaveArray(Component)) {
                @compileError("This function can't be called for zero-sized components");
            }
            std.debug.assert(self.has(Component));
            std.debug.assert(self.contains(entt));

            const entt_index = self.entities_to_component_index.getDenseIndex(entt.toInt());
            const component_arr = self.tryGetComponentArray(Component) catch unreachable;
            return @alignCast(std.mem.bytesAsValue(Component, component_arr.get(entt_index)));
        }

        pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {
            if (comptime !canHaveArray(Component)) {
                @compileError("This function can't be called for zero-sized components");
            }
            std.debug.assert(self.has(Component));
            std.debug.assert(self.contains(entt));

            const entt_index = self.entities_to_component_index.getDenseIndex(entt.toInt());
            return self.getComponentArrayPtr(Component).items[entt_index];
        }

        pub fn contains(self: *@This(), entt: options.EntityType) bool {
            return self.entities_to_component_index.contains(entt.toInt());
        }

        pub fn reserve(self: *@This(), entt: options.EntityType) !void {
            std.debug.assert(!self.contains(entt));

            var iter = self.signature.iterator();
            while (iter.nextTypeIdNonEmpty()) |tid| {
                const component_arr = try self.tryGetComponentArray(tid);
                try component_arr.reserve(self.allocator);
            }
            try self.entities_to_component_index.add(entt.toInt());
        }

        pub fn add(self: *@This(), entt: options.EntityType, values: anytype) !void {
            std.debug.assert(!self.contains(entt));

            inline for (values) |value| {
                const component_arr = try self.tryGetComponentArray(@TypeOf(value));
                try component_arr.append(self.allocator, value);
            }
            try self.entities_to_component_index.add(entt.toInt());
        }

        pub fn remove(self: *@This(), entt: Entity) void {
            std.debug.assert(self.contains(entt));

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
            std.debug.assert(self.contains(entt));
            std.debug.assert(!new_arch.contains(entt));
            try new_arch.reserve(entt);
            var iter_type_id = self.signature.iterator();
            while (iter_type_id.nextTypeId()) |tid| {
                if (new_arch.signature.has(tid)) {
                    const size = ComponentBitSet.getSize(tid);
                    if (size != 0) {
                        @memcpy(new_arch.getTypeId(tid, entt), self.getTypeId(tid, entt));
                    }
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

    var values = .{ @as(typeA, 4), typeC{}, typeE{ .a = 23, .b = 342 } };
    const entt_id = entity.EntityTypeFactory(.medium){ .index = 1, .version = 0 };
    try archetype.add(entt_id, &values);
    try std.testing.expect(archetype.contains(entt_id));
    archetype.remove(entt_id);
    try std.testing.expect(!archetype.contains(entt_id));
}
