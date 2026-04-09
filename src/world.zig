const std = @import("std");
const entity = @import("entity/entity.zig");
const archetype = @import("archetype/archetype.zig");
const commands = @import("commands/commands.zig");
const removed = @import("removed/removed.zig");
const sparsesets = @import("storage/sparseset/sparsesets.zig");
const dense_storage = @import("storage/dense_storage.zig");
const Tick = @import("types.zig").Tick;

pub const WorldOptions = struct {
    Components: type,
    Entity: type = entity.EntityTypeFactory(.medium),
    DenseStorageConfig: dense_storage.DenseStorageConfig,
};

pub fn World(comptime options: WorldOptions) type {
    return struct {
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const DenseStorageConfig = options.DenseStorageConfig;
        pub const Archetype = archetype.Archetype(.{
            .Entity = Entity,
            .Components = Components,
            .DenseStorageConfig = DenseStorageConfig,
        });
        pub const DenseStorage = Archetype.DenseStorage;
        pub const DenseStorageStore = dense_storage.DenseStorageStore(.{
            .World = @This(),
            .Config = DenseStorageConfig,
        });
        pub const ArchetypeStore = archetype.ArchetypeStore(.{
            .Archetype = Archetype,
            .DenseStorageStore = DenseStorageStore,
        });
        pub const Storage = Archetype.DenseStorage;
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
        pub const SparseSets = sparsesets.SparseSets(.{
            .PageSize = 4096,
            .Components = Components,
            .Entity = Entity,
        });

        allocator: std.mem.Allocator,
        entity_registry: EntityRegistry,
        storage_store: DenseStorageStore,
        archetype_store: ArchetypeStore,
        sparse_sets: SparseSets = .empty,
        queues: std.ArrayList(CommandsQueue) = .empty,
        removed: RemovedLog,
        global_tick: Tick = 0,

        pub fn init(allocator: std.mem.Allocator) !*@This() {
            const new = try allocator.create(@This());
            new.* = @This(){
                .allocator = allocator,
                .storage_store = @FieldType(@This(), "storage_store").init(allocator),
                // SAFETY: set right after, using storage_store address
                .archetype_store = undefined,
                .entity_registry = EntityRegistry.init(),
                .removed = RemovedLog.init(allocator),
            };
            new.archetype_store = @FieldType(@This(), "archetype_store").init(allocator, &new.storage_store);
            return new;
        }

        pub fn deinit(self: *@This()) void {
            self.archetype_store.deinit(self.allocator);
            self.storage_store.deinit(self.allocator);
            self.sparse_sets.deinit(self.allocator);
            self.entity_registry.deinit(self.allocator);
            self.deinitQueues();
            self.removed.deinit();
            self.allocator.destroy(self);
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
            var iter = self.archetype_store.iterator();
            while (iter.next()) |arch| {
                const arch_ptr = arch.*;
                count += arch_ptr.len();
            }
            return count;
        }

        /// Create a new entity and return it
        pub fn create(self: *@This()) !Entity {
            const empty_arch = try self.archetype_store.tryGetArchetypeFromSignature(self.allocator, Components.init(&.{}));
            return self.entity_registry.create(self.allocator, empty_arch);
        }

        pub inline fn valid(self: *@This(), entt: Entity) bool {
            return self.entity_registry.valid(entt);
        }

        pub fn destroy(self: *@This(), entt: Entity) !void {
            std.debug.assert(self.valid(entt));
            const location = self.entity_registry.getEntityLocation(entt);

            if (try location.storage.remove(self.allocator, location.dense_index)) |removal_result| {
                const swapped_entt_index, const new_slot_index = removal_result;
                self.entity_registry.setEntityDenseIndex(swapped_entt_index, new_slot_index);
            }

            try self.entity_registry.destroy(self.allocator, entt);
            location.version += 1;
        }

        fn moveToArchetype(self: *@This(), entt: Entity, from: *Archetype, to: *Archetype) !void {
            std.debug.assert(self.valid(entt));
            const location_ptr = self.entity_registry.getEntityLocation(entt);
            const move_to_result = try from.moveTo(self.allocator, entt, location_ptr, to, self.getTick(), &self.removed);
            // archetype vec
            {
                const archetype_removal_result = move_to_result.archetype_removal_result;
                self.entity_registry.setEntityArchetypeIndex(
                    archetype_removal_result[0],
                    archetype_removal_result[1],
                );
            }
            if (move_to_result.dense_removal_result) |removal_result| {
                // dense storage
                {
                    const dense_removal_result = removal_result;
                    self.entity_registry.setEntityDenseIndex(
                        dense_removal_result[0],
                        dense_removal_result[1],
                    );
                }
            }
        }

        pub fn has(self: *@This(), comptime Component: type, entt: Entity) bool {
            std.debug.assert(self.valid(entt));
            return switch (comptime Components.getStorageType(Component)) {
                .Dense => self.getEntityArchetype(entt).has(Component),
                .Sparse => self.sparse_sets.contains(entt, Component),
            };
        }

        pub fn remove(self: *@This(), comptime Component: type, entt: Entity) !void {
            std.debug.assert(self.valid(entt));
            const old_arch_sig = self.entity_registry.getEntitySignature(entt);
            var new_signature = old_arch_sig;
            new_signature.remove(Component);
            const new_arch = try self.archetype_store.tryGetArchetypeFromSignature(self.allocator, new_signature);
            const old_arch = self.archetype_store.getArchetypeFromSignature(old_arch_sig);

            // change archetype (and thus the signature) of this entity
            // will also move dense component data ONLY if added component is dense
            try self.moveToArchetype(entt, old_arch, new_arch);

            if (comptime Components.getStorageType(Component) == .Sparse) {
                try self.sparse_sets.remove(Component, entt, self.getTick(), &self.removed);
            }
        }

        /// using a slice of component type ids or component types, move entt to new archetype
        fn setNewSignature(self: *@This(), entt: Entity, new_signature: Components) !void {
            std.debug.assert(self.valid(entt));
            const old_arch_sig = self.entity_registry.getEntitySignature(entt);

            const new_arch = try self.archetype_store.tryGetArchetypeFromSignature(self.allocator, new_signature);
            const old_arch = self.archetype_store.getArchetypeFromSignature(old_arch_sig);

            // change archetype (and thus the signature) of this entity
            // will also move dense component data ONLY if added component is dense
            try self.moveToArchetype(entt, old_arch, new_arch);

            // remove from these old sparse sets
            var iter = old_arch_sig
                .difference(new_signature)
                .applyStorageTypeMask(.Sparse)
                .iterator();
            while (iter.nextTypeId()) |tid| {
                try self.sparse_sets.remove(tid, entt, self.getTick(), &self.removed);
            }

            // reserve at these new sparse sets
            iter = new_signature
                .difference(old_arch_sig)
                .applyStorageTypeMask(.Sparse)
                .iterator();
            while (iter.nextTypeId()) |tid| {
                try self.sparse_sets.reserve(self.allocator, tid, entt);
                self.sparse_sets.setMetadataToCurrentTick(tid, entt, self.getTick());
            }
        }
        pub fn add(self: *@This(), entt: Entity, value: anytype) !void {
            std.debug.assert(self.valid(entt));
            const Component = @TypeOf(value);
            const old_arch_sig = self.entity_registry.getEntitySignature(entt);

            var new_signature = old_arch_sig;
            new_signature.add(Component);

            const new_arch = try self.archetype_store.tryGetArchetypeFromSignature(self.allocator, new_signature);
            const old_arch = self.archetype_store.getArchetypeFromSignature(old_arch_sig);

            // change archetype (and thus the signature) of this entity
            // will also move dense component data ONLY if added component is dense
            try self.moveToArchetype(entt, old_arch, new_arch);

            if (comptime Components.getStorageType(@TypeOf(value)) == .Sparse) {
                try self.sparse_sets.reserve(self.allocator, @TypeOf(value), entt);
                self.sparse_sets.setMetadataToCurrentTick(Component, entt, self.getTick());
            }
            if (comptime @sizeOf(Component) != 0) {
                self.get(Component, entt).* = value;
            }
        }

        pub fn get(self: *@This(), comptime Component: type, entt: Entity) *Component {
            std.debug.assert(self.valid(entt));
            return switch (comptime Components.getStorageType(Component)) {
                .Dense => dense: {
                    const location = self.entity_registry.getEntityLocation(entt);
                    break :dense location.storage.get(Component, location.dense_index);
                },
                .Sparse => self.sparse_sets.get(Component, entt),
            };
        }

        pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) *Component {
            std.debug.assert(self.valid(entt));
            return switch (comptime Components.getStorageType(Component)) {
                .Dense => dense: {
                    const location = self.entity_registry.getEntityLocation(entt);
                    break :dense location.storage.getConst(Component, location.dense_index);
                },
                .Sparse => self.sparse_sets.getConst(entt.index),
            };
        }

        pub fn getDenseStorageAddress(self: *@This(), entt: Entity) DenseStorage.StorageAddress {
            const location = self.entity_registry.getEntityLocation(entt).*;
            return .{ location.storage, location.dense_index };
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
            var iter = queue.iterator();
            main_command_loop: while (iter.next()) |ctx_or_despawn| {
                const entt, var signature = switch (ctx_or_despawn) {
                    .despawn => |d| {
                        try self.destroy(d.entt);
                        continue :main_command_loop;
                    },
                    .context => |ctx| switch (ctx.id) {
                        .entity => |e| .{ e, self.entity_registry.getEntitySignature(e) },
                        .placeholder => .{ try self.create(), Components.initEmpty() },
                    },
                    else => @panic("command queue has invalid order"),
                };
                if (comptime Components.Len == 0) continue :main_command_loop;

                const context_slice = queue.getContextSlice(&iter);
                var sig_change: bool = false;
                // setup new signature
                for (context_slice) |command| {
                    switch (command) {
                        .add => |a| {
                            sig_change = true;
                            const tid: Components.ComponentTypeId = std.meta.activeTag(a);
                            signature.add(tid);
                        },
                        .remove => |tid| {
                            sig_change = true;
                            signature.remove(tid);
                        },
                        else => @panic("This shouldn't be part of the context slice"),
                    }
                }
                // populate with values
                try self.setNewSignature(entt, signature);
                if (!sig_change) continue :main_command_loop;

                for (context_slice) |command| {
                    switch (command) {
                        .add => |a| {
                            switch (a) {
                                inline else => |v| {
                                    if (comptime @sizeOf(@TypeOf(v)) != 0) {
                                        self.get(@TypeOf(v), entt).* = v;
                                    }
                                },
                            }
                        },
                        // was already removed
                        .remove => {},
                        else => @panic("This shouldn't be part of the context slice"),
                    }
                }
            }
        }
    };
}

test "all" {
    _ = @import("archetype/archetype.zig");
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
