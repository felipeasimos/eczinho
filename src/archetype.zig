const std = @import("std");
const sparseset = @import("sparse_set.zig");
const entity = @import("entity.zig");
const components = @import("components.zig");

pub const ArchetypeOptions = struct {
    ComponentBitSet: type,
    Signature: []const type,
    EntityType: type,
};

/// use ArchetypeOptions as options
pub fn Archetype(comptime options: ArchetypeOptions) type {
    const num_active_components = options.Signature.len;
    const signature = options.ComponentBitSet.init(options.Signature);
    return struct {
        const Signature = signature;
        component_arrays: [num_active_components]std.ArrayList(u8),
        entities_to_component_index: sparseset.SparseSet(.{
            .T = options.EntityType.Int,
            .PageMask = options.EntityType.entity_mask,
        }),
        allocator: std.mem.Allocator,

        fn toComponentArrayIndex(comptime Component: type) usize {
            if (std.mem.indexOfScalar(type, options.Signature, Component)) |idx| {
                return idx;
            }
            @compileError(std.fmt.print("Component {} doesn't belong in archetype {}", .{ Component, options.Signature }));
        }

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .component_arrays = .{std.ArrayList(u8).empty} ** num_active_components,
                .entities_to_component_index = @FieldType(@This(), "entities_to_component_index").init(alloc),
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            inline for (&self.component_arrays, options.Signature) |*arr, SigType| {
                @as(*std.ArrayList(SigType), @ptrCast(arr)).deinit(self.allocator);
            }
            self.entities_to_component_index.deinit();
        }

        pub fn len(self: *@This()) usize {
            return self.entities_to_component_index.len();
        }

        pub fn has(comptime Component: type) bool {
            return comptime std.mem.indexOfScalar(type, options.Signature, Component) != null;
        }

        pub fn contains(self: *@This(), entt: options.EntityType) bool {
            return self.entities_to_component_index.contains(entt.toInt());
        }

        pub fn add(self: *@This(), entt: options.EntityType, values: anytype) !void {
            inline for (&self.component_arrays, options.Signature, values) |*arr, SigType, value| {
                if (@sizeOf(SigType) != 0) {
                    try @as(*std.ArrayList(SigType), @ptrCast(arr)).append(self.allocator, value);
                }
            }
            try self.entities_to_component_index.add(entt.toInt());
        }

        pub fn remove(self: *@This(), entt: options.EntityType) void {
            const entt_index = self.entities_to_component_index.remove(entt.toInt());
            inline for (&self.component_arrays, options.Signature) |*arr, SigType| {
                if (@sizeOf(SigType) != 0) {
                    _ = @as(*std.ArrayList(SigType), @ptrCast(arr)).swapRemove(entt_index);
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
