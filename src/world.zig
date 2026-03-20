const std = @import("std");
const entity = @import("entity/entity.zig");
const archetype = @import("archetype.zig");
const commands = @import("commands/commands.zig");
const removed = @import("removed/removed.zig");
const Tick = @import("types.zig").Tick;

pub const WorldOptions = struct {
    Components: type,
    Entity: type = entity.EntityTypeFactory(.medium),
};

pub fn World(comptime options: WorldOptions) type {
    return struct {
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const Archetype = archetype.Archetype(.{
            .Entity = Entity,
            .Components = Components,
        });
        pub const Storage = Archetype.Storage;
        pub const EntityLocation = entity.EntityLocation(.{
            .Archetype = Archetype,
        });
        pub const EntityRegistry = entity.EntityRegistry(.{
            .Archetype = Archetype,
            .EntityLocation = EntityLocation,
        });
        pub const CommandsQueue = commands.CommandsQueue(.{
            .Entity = Entity,
            .Components = Components,
        });
        pub const RemovedLog = removed.RemovedLog(.{
            .Components = Components,
            .Entity = Entity,
        });

        allocator: std.mem.Allocator,
        entity_registry: EntityRegistry,
        archetypes: std.AutoHashMap(Components, *Archetype),
        queues: std.ArrayList(CommandsQueue) = .empty,
        removed: RemovedLog,
        global_tick: Tick = 0,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .archetypes = @FieldType(@This(), "archetypes").init(allocator),
                .entity_registry = EntityRegistry.init(),
                .removed = RemovedLog.init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            var iter = self.archetypes.valueIterator();
            while (iter.next()) |arch| {
                const arch_ptr = arch.*;
                arch_ptr.deinit(self.allocator);
                self.allocator.destroy(arch_ptr);
            }
            self.archetypes.deinit();
            self.entity_registry.deinit(self.allocator);
            self.deinitQueues();
            self.removed.deinit();
        }

        fn deinitQueues(self: *@This()) void {
            for (self.queues.items) |*queue| {
                queue.deinit();
            }
            self.queues.deinit(self.allocator);
            self.queues = .empty;
        }

        pub fn tick(self: *@This()) void {
            self.global_tick +%= 1;
        }
        pub fn getTick(self: *const @This()) Tick {
            return self.global_tick;
        }

        pub fn len(self: *@This()) usize {
            var count: usize = 0;
            var iter = self.archetypes.valueIterator();
            while (iter.next()) |arch| {
                const arch_ptr = arch.*;
                count += arch_ptr.len();
            }
            return count;
        }

        pub fn getArchetypeFromSignature(self: *@This(), signature: Components) *Archetype {
            return self.archetypes.get(signature).?;
        }

        pub fn tryGetArchetypeFromSignature(self: *@This(), signature: Components) !*Archetype {
            const entry = try self.archetypes.getOrPut(signature);
            if (entry.found_existing) {
                return entry.value_ptr.*;
            }
            const arch_ptr = try self.allocator.create(Archetype);
            arch_ptr.* = try Archetype.init(self.allocator, signature);
            entry.value_ptr.* = arch_ptr;
            return arch_ptr;
        }

        /// Create a new entity and return it
        pub fn create(self: *@This()) !Entity {
            const empty_arch = try self.tryGetArchetypeFromSignature(Components.init(&.{}));
            return self.entity_registry.create(self.allocator, empty_arch);
        }

        pub inline fn valid(self: *@This(), entt: Entity) bool {
            return self.entity_registry.valid(entt);
        }

        pub fn destroy(self: *@This(), entt: Entity) !void {
            std.debug.assert(self.valid(entt));
            const location = self.entity_registry.getEntityLocation(entt);
            if (try location.chunk.remove(self.allocator, @intCast(location.chunk_slot_index))) |removal_result| {
                const swapped_entt, const new_slot_index = removal_result;
                self.entity_registry.setEntityIndex(swapped_entt, new_slot_index, .Dense);
            }
            try self.entity_registry.destroy(self.allocator, entt);
            location.version += 1;
        }

        fn moveTo(self: *@This(), entt: Entity, from: *Archetype, to: *Archetype) !void {
            std.debug.assert(self.valid(entt));
            const location_ptr = self.entity_registry.getEntityLocation(entt);
            if (try from.moveTo(self.allocator, entt, location_ptr, to, self.getTick(), &self.removed)) |removal_result| {
                const swapped_entt, const new_slot_index = removal_result;
                self.entity_registry.setEntityIndex(swapped_entt, new_slot_index, .Dense);
            }
        }

        pub fn has(self: *@This(), comptime Component: type, entt: Entity) bool {
            std.debug.assert(self.valid(entt));
            return self.getEntityArchetype(entt).has(Component);
        }

        pub fn remove(self: *@This(), tid_or_component: anytype, entt: Entity) !void {
            std.debug.assert(self.valid(entt));
            const old_arch_sig = self.entity_registry.getEntitySignature(entt);
            var new_signature = old_arch_sig;
            new_signature.remove(tid_or_component);
            const new_arch = self.getArchetypeFromSignature(new_signature);
            const old_arch = self.getArchetypeFromSignature(old_arch_sig);
            try self.moveTo(entt, old_arch, new_arch);
        }

        pub fn add(self: *@This(), entt: Entity, value: anytype) !void {
            std.debug.assert(self.valid(entt));
            const Component = @TypeOf(value);

            const old_arch_sig = self.entity_registry.getEntitySignature(entt);

            var new_signature = old_arch_sig;
            new_signature.add(Component);

            const new_arch = try self.tryGetArchetypeFromSignature(new_signature);
            const old_arch = self.getArchetypeFromSignature(old_arch_sig);

            try self.moveTo(entt, old_arch, new_arch);
            if (@sizeOf(Component) != 0) {
                self.get(Component, entt).* = value;
            }
        }

        pub fn get(self: *@This(), comptime Component: type, entt: Entity) *Component {
            std.debug.assert(self.valid(entt));
            const location = self.entity_registry.getEntityLocation(entt);
            return location.chunk.get(Component, location.chunk_slot_index);
        }

        pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {
            std.debug.assert(self.valid(entt));
            const location = self.entity_registry.getEntityLocation(entt);
            return location.chunk.getConst(Component, location.chunk_slot_index);
        }

        pub fn createQueue(self: *@This()) !*CommandsQueue {
            try self.queues.append(self.allocator, CommandsQueue.init(self.allocator));
            return &self.queues.items[self.queues.items.len - 1];
        }

        pub fn sync(self: *@This()) !void {
            // swap removed
            self.removed.swap();
            // sync queues
            for (self.queues.items) |*queue| {
                try self.syncQueue(queue);
            }
            self.deinitQueues();
            self.tick();
        }

        fn syncQueue(self: *@This(), queue: *CommandsQueue) !void {
            std.debug.assert(queue.commands.items.len == 0 or
                queue.commands.items[0] == .context or
                queue.commands.items[0] == .despawn);

            // deal with despawn case
            if (queue.commands.items.len == 1 and queue.commands.items[0] == .despawn) {
                const despawn = queue.commands.items[0].despawn;
                try self.destroy(despawn.entt);
                return;
            }
            var iter = queue.iterator();
            while (iter.next()) |ctx| {
                const entt = switch (ctx.context.id) {
                    .entity => |e| e,
                    .placeholder => try self.create(),
                };
                context_loop: while (iter.next()) |comm| {
                    switch (comm) {
                        .add => |a| {
                            if (comptime Components.Len != 0) {
                                switch (a) {
                                    inline else => |v| {
                                        try self.add(entt, v);
                                    },
                                }
                            }
                        },
                        .remove => |type_id| {
                            try self.remove(type_id, entt);
                        },
                        .despawn => |d| {
                            try self.destroy(d.entt);
                            break :context_loop;
                        },
                        .context => {
                            // rollback so the outer loop iteration catches
                            // and use this context
                            iter.rollback();
                            break :context_loop;
                        },
                    }
                }
            }
        }
    };
}

test "all" {
    _ = @import("archetype.zig");
    _ = @import("array.zig");
    _ = @import("components.zig");
    _ = @import("entity/entity.zig");
}

test World {
    const ComponentsFactory = @import("components.zig").Components;
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };

    var world = World(.{
        .Components = ComponentsFactory(&.{ typeA, typeB, typeC, typeD, typeE }),
        .Entity = entity.EntityTypeFactory(.medium),
    }).init(std.testing.allocator);
    defer world.deinit();

    const entt_id = try world.create();
    try world.add(entt_id, typeE{ .a = 1, .b = 2 });

    try std.testing.expect(world.has(typeE, entt_id));
    try std.testing.expect(!world.has(typeD, entt_id));

    try std.testing.expectEqual(1, world.get(typeE, entt_id).a);
    try std.testing.expectEqual(2, world.get(typeE, entt_id).b);

    try std.testing.expectEqual(1, world.getConst(typeE, entt_id).a);
    try std.testing.expectEqual(2, world.getConst(typeE, entt_id).b);
}

test "world initialization test" {
    const ComponentsFactory = @import("components.zig").Components;
    var world = World(.{
        .Components = ComponentsFactory(&.{ u64, bool, struct {} }),
        .Entity = entity.EntityTypeFactory(.small),
    }).init(std.testing.allocator);
    defer world.deinit();
}

test "world remove test" {
    const ComponentsFactory = @import("components.zig").Components;
    var world = World(.{
        .Components = ComponentsFactory(&.{ u64, bool, struct {} }),
        .Entity = entity.EntityTypeFactory(.small),
    }).init(std.testing.allocator);
    defer world.deinit();

    const entt_id = try world.create();
    try world.add(entt_id, @as(u64, 7));
    try world.remove(u64, entt_id);
    try std.testing.expectEqual(1, world.len());
    const another_id = try world.create();
    try std.testing.expectEqual(2, world.len());
    try world.add(another_id, true);
}
