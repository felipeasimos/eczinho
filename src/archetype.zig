const std = @import("std");
const sparseset = @import("sparse_set.zig");
const entity = @import("entity.zig");
const type_id = @import("type_id.zig");
const components = @import("components.zig");

pub const ArchetypeOptions = struct {
    ComponentBitSet: type,
    Signature: []const type,
    EntityType: type,
};

/// use ArchetypeOptions as options
pub fn Archetype(comptime options: ArchetypeOptions) type {
    return struct {
        const Entity = options.EntityType;
        pub const Signature = options.ComponentBitSet.init(options.Signature);
        signature: options.ComponentBitSet = Signature,
        components: std.AutoHashMap(type_id.TypeId, std.ArrayList(u8)),
        entities_to_component_index: sparseset.SparseSet(.{
            .T = options.EntityType.Int,
            .PageMask = options.EntityType.entity_mask,
        }),
        allocator: std.mem.Allocator,

        fn tryGetComponentArrayPtr(self: *@This(), comptime Component: type) !?*std.ArrayList(Component) {
            const entry = try self.components.getOrPutValue(type_id.hash(Component), .empty);
            return @ptrCast(entry.value_ptr);
        }

        fn getComponentArrayPtr(self: *@This(), comptime Component: type) ?*std.ArrayList(Component) {
            return @ptrCast(self.components.getEntry(type_id.hash(Component)).?.value_ptr);
        }

        fn canHaveArray(comptime Component: type) bool {
            return comptime @sizeOf(Component) != 0;
        }

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .components = @FieldType(@This(), "components").init(alloc),
                .entities_to_component_index = @FieldType(@This(), "entities_to_component_index").init(alloc),
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            inline for (options.Signature) |Component| {
                if (comptime !canHaveArray(Component)) {
                    continue;
                }
                if (self.getComponentArrayPtr(Component)) |arr| {
                    arr.deinit(self.allocator);
                }
            }
            self.components.deinit();
            self.entities_to_component_index.deinit();
        }

        pub fn len(self: *@This()) usize {
            return self.entities_to_component_index.len();
        }

        pub fn has(comptime Component: type) bool {
            return comptime std.mem.indexOfScalar(type, options.Signature, Component) != null;
        }

        pub fn entities(self: *@This()) []Entity {
            return self.entities_to_component_index.items();
        }

        pub fn get(self: *@This(), comptime Component: type, entt: Entity) Component {
            if (comptime !canHaveArray(Component)) {
                @compileError("This function can't be called for zero-sized components");
            }
            comptime std.debug.assert(has(Component));
            std.debug.assert(self.contains(entt.toInt()));

            const entt_index = self.entities_to_component_index.getDenseIndex(entt.toInt());
            return &self.getComponentArrayPtr(Component).items[entt_index];
        }

        pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {
            if (comptime !canHaveArray(Component)) {
                @compileError("This function can't be called for zero-sized components");
            }
            comptime std.debug.assert(has(Component));
            std.debug.assert(self.contains(entt.toInt()));

            const entt_index = self.entities_to_component_index.getDenseIndex(entt.toInt());
            return self.getComponentArrayPtr(Component).items[entt_index];
        }

        pub fn contains(self: *@This(), entt: options.EntityType) bool {
            return self.entities_to_component_index.contains(entt.toInt());
        }

        pub fn add(self: *@This(), entt: options.EntityType, values: anytype) !void {
            std.debug.assert(!self.contains(entt));

            inline for (options.Signature, values) |Component, value| {
                if (comptime !canHaveArray(Component)) {
                    continue;
                }
                if (try self.tryGetComponentArrayPtr(Component)) |arr| {
                    try arr.append(self.allocator, value);
                }
            }
            try self.entities_to_component_index.add(entt.toInt());
        }

        pub fn remove(self: *@This(), entt: Entity) void {
            std.debug.assert(self.contains(entt));

            const entt_index = self.entities_to_component_index.remove(entt.toInt());
            inline for (options.Signature) |Component| {
                if (comptime !canHaveArray(Component)) {
                    continue;
                }
                if (self.getComponentArrayPtr(Component)) |arr| {
                    _ = arr.swapRemove(entt_index);
                }
            }
        }
    };
}

test Archetype {
    _ = @import("iter.zig");
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };
    const ArchetypeType = Archetype(.{
        .EntityType = entity.EntityTypeFactory(.medium),
        .ComponentBitSet = components.Components(&[_]type{ typeA, typeB, typeC, typeD, typeE }),
        .Signature = &[_]type{ typeA, typeC, typeD, typeE },
    });
    var archetype = ArchetypeType.init(std.testing.allocator);
    defer archetype.deinit();

    try std.testing.expect(ArchetypeType.has(typeA));
    try std.testing.expect(!ArchetypeType.has(typeB));
    try std.testing.expect(ArchetypeType.has(typeC));
    try std.testing.expect(ArchetypeType.has(typeD));
    try std.testing.expect(ArchetypeType.has(typeE));

    var values = .{ 4, typeC{}, typeD{ .a = 34 }, typeE{ .a = 23, .b = 342 } };
    const entt_id = entity.EntityTypeFactory(.medium){ .index = 1, .version = 0 };
    try archetype.add(entt_id, &values);
    try std.testing.expect(archetype.contains(entt_id));
    archetype.remove(entt_id);
    try std.testing.expect(!archetype.contains(entt_id));
}
