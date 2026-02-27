const std = @import("std");
const entity = @import("entity.zig");
const archetype = @import("archetype.zig");
const commands = @import("commands/commands.zig");
const removed = @import("removed/removed.zig");
const Tick = @import("types.zig").Tick;

pub const RegistryOptions = struct {
    Components: type,
    Entity: type = entity.EntityTypeFactory(.medium),
};

pub fn Registry(comptime options: RegistryOptions) type {
    return struct {
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const Archetype = archetype.Archetype(.{
            .Entity = Entity,
            .Components = Components,
        });
        pub const Chunk = Archetype.Chunk;
        pub const CommandsQueue = commands.CommandsQueue(.{
            .Entity = Entity,
            .Components = Components,
        });
        pub const RemovedLog = removed.RemovedLog(.{
            .Components = Components,
            .Entity = Entity,
        });

        pub const EntityLocation = struct {
            // pointer to archetype
            arch: *Archetype,
            // if entity is alive, this points to its chunk
            chunk: *Chunk,
            // index inside the chunk
            slot_index: u16,
            // current (if alive) or next (if dead) generation of an entity index.
            version: options.Entity.Version = 0,
        };

        allocator: std.mem.Allocator,
        archetypes: std.AutoHashMap(Components, *Archetype),
        /// entity index to -> generations + archetype
        entities_to_locations: std.ArrayList(EntityLocation) = .empty,
        free_entity_list: std.ArrayList(Entity.Index) = .empty,
        queues: std.ArrayList(CommandsQueue) = .empty,
        removed: RemovedLog,
        global_tick: Tick = 0,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .archetypes = @FieldType(@This(), "archetypes").init(allocator),
                .removed = RemovedLog.init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            var iter = self.archetypes.valueIterator();
            while (iter.next()) |arch| {
                const arch_ptr = arch.*;
                arch_ptr.deinit();
                self.allocator.destroy(arch_ptr);
            }
            self.archetypes.deinit();
            self.entities_to_locations.deinit(self.allocator);
            self.free_entity_list.deinit(self.allocator);
            self.deinitQueues();
            self.removed.deinit();
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

        fn getEntityArchetype(self: *@This(), entt: Entity) *Archetype {
            std.debug.assert(self.valid(entt));
            return self.entities_to_locations.items[entt.index].arch;
        }

        fn getEntitySignature(self: *@This(), entt: Entity) Components {
            std.debug.assert(self.valid(entt));
            return self.entities_to_locations.items[entt.index].arch.signature;
        }
        fn optGetEntitySignature(self: *@This(), entt: Entity) ?Components {
            std.debug.assert(self.valid(entt));
            if (self.entities_to_locations.items[entt.index].signature) |sig| {
                return sig;
            }
            return null;
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

        pub fn valid(self: *@This(), id: Entity) bool {
            if (id.index >= self.entities_to_locations.items.len) return false;
            return self.entities_to_locations.items[id.index].version == id.version;
        }

        /// Create a new entity and return it
        pub fn create(self: *@This()) !Entity {
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
                try self.entities_to_locations.append(self.allocator, undefined);
                break :new_entity Entity{
                    .index = new_index,
                    .version = 0,
                };
            };
            // update entity_to_locations with new id
            const empty_arch = try self.tryGetArchetypeFromSignature(Components.init(&.{}));

            const chunk, const slot_index = try empty_arch.reserve(entity_id);
            self.entities_to_locations.items[@intCast(entity_id.index)] = EntityLocation{
                .arch = empty_arch,
                .version = entity_id.version,
                .chunk = chunk,
                .slot_index = @intCast(slot_index),
            };

            return entity_id;
        }

        inline fn correctEntityIndex(self: *@This(), entt: Entity, slot_index: usize) void {
            self.entities_to_locations.items[entt.index].slot_index = @intCast(slot_index);
        }

        pub fn destroy(self: *@This(), entt: Entity) !void {
            std.debug.assert(self.valid(entt));
            const location = &self.entities_to_locations.items[entt.index];
            const swapped_entt, const new_slot_index = location.chunk.remove(@intCast(location.slot_index));
            self.correctEntityIndex(swapped_entt, new_slot_index);
            try self.free_entity_list.append(self.allocator, entt.index);
            location.version += 1;
        }

        fn moveTo(self: *@This(), entt: Entity, from: *Archetype, to: *Archetype) !void {
            std.debug.assert(self.valid(entt));
            const location_ptr = &self.entities_to_locations.items[entt.index];
            const swapped_entt, const new_slot_index = try from.moveTo(entt, location_ptr, to, self.getTick(), &self.removed);
            self.correctEntityIndex(swapped_entt, new_slot_index);
        }

        pub fn has(self: *@This(), comptime Component: type, entt: Entity) bool {
            std.debug.assert(self.valid(entt));
            return self.getEntityArchetype(entt).has(Component);
        }

        pub fn remove(self: *@This(), tid_or_component: anytype, entt: Entity) !void {
            std.debug.assert(self.valid(entt));
            const old_arch_sig = self.getEntitySignature(entt);
            var new_signature = old_arch_sig;
            new_signature.remove(tid_or_component);
            const new_arch = self.getArchetypeFromSignature(new_signature);
            const old_arch = self.getArchetypeFromSignature(old_arch_sig);
            try self.moveTo(entt, old_arch, new_arch);
        }

        pub fn add(self: *@This(), entt: Entity, value: anytype) !void {
            std.debug.assert(self.valid(entt));
            const Component = @TypeOf(value);

            const old_arch_sig = self.getEntitySignature(entt);

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
            const location = self.entities_to_locations.items[entt.index];
            return location.chunk.get(Component, location.slot_index);
        }

        pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {
            std.debug.assert(self.valid(entt));
            const location = self.entities_to_locations.items[entt.index];
            return location.chunk.getConst(Component, location.slot_index);
        }

        pub fn createQueue(self: *@This()) !*CommandsQueue {
            try self.queues.append(self.allocator, CommandsQueue.init(self.allocator));
            return &self.queues.items[self.queues.items.len - 1];
        }

        fn deinitQueues(self: *@This()) void {
            for (self.queues.items) |*queue| {
                queue.deinit();
            }
            self.queues.deinit(self.allocator);
            self.queues = .empty;
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
            std.debug.assert(queue.commands.items.len == 0 or queue.commands.items[0] == .context or queue.commands.items[0] == .despawn);

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
                    .placeholder => |_| try self.create(),
                };
                context_loop: while (iter.next()) |comm| {
                    switch (comm) {
                        .add => |a| switch (a) {
                            inline else => |v| {
                                try self.add(entt, v);
                            },
                        },
                        .remove => |type_id| {
                            try self.remove(type_id, entt);
                        },
                        .despawn => |d| {
                            try self.destroy(d.entt);
                            break :context_loop;
                        },
                        .context => |_| {
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
    _ = @import("sparse_set.zig");
    _ = @import("archetype.zig");
    _ = @import("array.zig");
    _ = @import("components.zig");
    _ = @import("entity.zig");
}

test Registry {
    const ComponentsFactory = @import("components.zig").Components;
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };

    var registry = Registry(.{
        .Components = ComponentsFactory(&.{ typeA, typeB, typeC, typeD, typeE }),
        .Entity = entity.EntityTypeFactory(.medium),
    }).init(std.testing.allocator);
    defer registry.deinit();

    const entt_id = try registry.create();
    try registry.add(entt_id, typeE{ .a = 1, .b = 2 });

    try std.testing.expect(registry.has(typeE, entt_id));
    try std.testing.expect(!registry.has(typeD, entt_id));

    try std.testing.expectEqual(1, registry.get(typeE, entt_id).a);
    try std.testing.expectEqual(2, registry.get(typeE, entt_id).b);

    try std.testing.expectEqual(1, registry.getConst(typeE, entt_id).a);
    try std.testing.expectEqual(2, registry.getConst(typeE, entt_id).b);
}

test "registry initialization test" {
    const ComponentsFactory = @import("components.zig").Components;
    var registry = Registry(.{
        .Components = ComponentsFactory(&.{ u64, bool, struct {} }),
        .Entity = entity.EntityTypeFactory(.small),
    }).init(std.testing.allocator);
    defer registry.deinit();
}

test "registry remove test" {
    const ComponentsFactory = @import("components.zig").Components;
    var registry = Registry(.{
        .Components = ComponentsFactory(&.{ u64, bool, struct {} }),
        .Entity = entity.EntityTypeFactory(.small),
    }).init(std.testing.allocator);
    defer registry.deinit();

    const entt_id = try registry.create();
    try registry.add(entt_id, @as(u64, 7));
    try registry.remove(u64, entt_id);
    const another_id = try registry.create();
    try registry.add(another_id, true);
}
