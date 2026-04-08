const std = @import("std");
const entity = @import("entity/entity.zig");
const components = @import("components.zig");
const Tick = @import("types.zig").Tick;
const WorldFactory = @import("world.zig").World;
const dense_storage = @import("storage/dense_storage.zig");

pub const ArchetypeOptions = struct {
    Components: type,
    Entity: type,
    DenseStorageConfig: dense_storage.DenseStorageConfig,
};

/// use ArchetypeOptions as options
pub fn Archetype(comptime options: ArchetypeOptions) type {
    return struct {
        const Self = @This();
        pub const ComponentTypeId = options.Components.ComponentTypeId;
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const DenseStorageConfig = options.DenseStorageConfig;
        pub const World = WorldFactory(.{
            .Components = Components,
            .Entity = Entity,
            .DenseStorageConfig = DenseStorageConfig,
        });
        pub const EntityLocation = World.EntityLocation;
        pub const DenseStorage = dense_storage.DenseStorage(.{
            .World = World,
            .Config = options.DenseStorageConfig,
        });
        const StorageAddress = DenseStorage.StorageAddress;

        /// only contains components that both belong to this archetype AND have dense storage set
        signature: Components,
        storage: DenseStorage,
        entities: std.ArrayList(Entity) = .empty,

        inline fn hash(tid_or_component: anytype) ComponentTypeId {
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                return tid_or_component;
            } else if (comptime Components.isComponent(tid_or_component)) {
                return Components.hash(tid_or_component);
            }
        }

        pub fn init(allocator: std.mem.Allocator, sig: Components) !@This() {
            return .{
                .storage = try DenseStorage.init(allocator, sig),
                .signature = sig,
            };
        }

        pub inline fn postInit(self: *@This()) void {
            if (comptime @hasDecl(DenseStorage, "postInit")) {
                self.storage.postInit(self);
            }
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.storage.deinit(allocator);
            self.entities.deinit(allocator);
        }

        /// return the number of entities in the archetype
        pub inline fn len(self: *@This()) usize {
            return self.entities.items.len;
        }

        pub inline fn has(self: *@This(), tid_or_component: anytype) bool {
            return self.signature.has(tid_or_component);
        }

        pub fn reserve(
            self: *@This(),
            allocator: std.mem.Allocator,
            entt: Entity,
            location: *EntityLocation,
        ) !DenseStorage.StorageAddress {
            location.archetype_vec_index = self.len();
            try self.entities.append(allocator, entt);
            return self.storage.reserve(allocator, entt);
        }

        pub const MoveToResult = struct {
            archetype_removal_result: struct { usize, usize },
            dense_removal_result: ?DenseStorage.RemovalResult,
        };
        /// move entity to new archetype.
        /// this function only copies the values from dense components that exist in both archetypes.
        /// dense components only present in 'new_arch' must be set after this call.
        /// no move happens if the only difference between the two archetypes is sparse components
        /// returns swapped entity index and its new slot index (because of the remove)
        pub fn moveTo(
            self: *@This(),
            allocator: std.mem.Allocator,
            entt: Entity,
            location: *EntityLocation,
            new_arch: *@This(),
            current_tick: Tick,
            removed_logs: anytype,
        ) !MoveToResult {
            const old_archetype_vec_index = location.archetype_vec_index;
            const new_storage, const new_slot_index = try new_arch.reserve(
                allocator,
                entt,
                location,
            );
            const old_slot_index = location.dense_index;

            const old_dense_signature = self.signature.applyStorageTypeMask(.Dense);
            const new_dense_signature = new_arch.signature.applyStorageTypeMask(.Dense);

            const old_storage = location.storage;

            // both archetypes have the non empty component -> just copy it
            {
                var intersection = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyNonEmptyMask();
                var iter_intersection = intersection.iterator();
                while (iter_intersection.nextTypeId()) |tid| {
                    const old_addr = old_storage.getComponentWithTypeId(tid, old_slot_index);
                    const new_addr = new_storage.getComponentWithTypeId(tid, new_slot_index);
                    @memcpy(new_addr, old_addr);
                }
            }
            // removed components with removed metadata -> add to removed logs
            {
                var removed = old_dense_signature
                    .difference(new_dense_signature)
                    .applyRemovedMask();
                var iter_removed = removed.iterator();
                while (iter_removed.nextTypeId()) |tid| {
                    try removed_logs.addRemoved(tid, entt, current_tick);
                }
            }
            // already existing components with added metadata -> copy metadata
            {
                var existing_with_added = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyAddedMask();
                var iter = existing_with_added.iterator();
                while (iter.nextTypeId()) |tid| {
                    new_storage
                        .getAddedArray(tid)[new_slot_index] = old_storage
                        .getAddedArray(tid)[old_slot_index];
                }
            }
            // already existing non empty components with changed metadata -> copy metadata
            {
                var existing_with_changed = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyChangedMask();
                var iter = existing_with_changed.iterator();
                while (iter.nextTypeId()) |tid| {
                    new_storage
                        .getChangedArray(tid)[new_slot_index] = old_storage
                        .getChangedArray(tid)[old_slot_index];
                }
            }
            // newly added components with added metadata -> update metadata
            {
                var newly_added = new_dense_signature
                    .difference(old_dense_signature)
                    .applyAddedMask();
                var iter = newly_added.iterator();
                while (iter.nextTypeId()) |tid| {
                    new_storage.getAddedArray(tid)[new_slot_index] = current_tick;
                }
            }
            // newly added component with changed metadata -> update metadata
            {
                var newly_added = new_dense_signature
                    .difference(old_dense_signature)
                    .applyChangedMask();
                var iter = newly_added.iterator();
                while (iter.nextTypeId()) |tid| {
                    new_storage.getChangedArray(tid)[new_slot_index] = current_tick;
                }
            }
            const removed_result = try old_storage.remove(allocator, old_slot_index) orelse null;
            location.dense_index = new_slot_index;
            location.storage = new_storage;
            location.arch = new_arch;
            const archetype_swapped_entt = self.entities.getLast();
            _ = self.entities.swapRemove(old_archetype_vec_index);
            return MoveToResult{
                .archetype_removal_result = .{
                    archetype_swapped_entt.index,
                    old_archetype_vec_index,
                },
                .dense_removal_result = removed_result,
            };
        }

        pub fn iterator(
            self: *@This(),
            comptime ReturnTypes: []const type,
            comptime Added: []const type,
            comptime Changed: []const type,
            last_run: Tick,
            current_run: Tick,
        ) Iterator(ReturnTypes, Added, Changed) {
            return Iterator(ReturnTypes, Added, Changed).init(self, last_run, current_run);
        }

        pub fn Iterator(
            comptime ReturnTypes: []const type,
            comptime Added: []const type,
            comptime Changed: []const type,
        ) type {
            for (ReturnTypes) |Type| {
                if (@sizeOf(Type) == 0) {
                    @compileError("Can't iterate over zero sized component array");
                }
            }
            const Tuple = @Tuple(ReturnTypes);
            return struct {
                last_run: Tick,
                current_run: Tick,
                iter: DenseStorage.Iterator,
                pub fn init(archetype: *Self, last_run: Tick, current_run: Tick) @This() {
                    return .{
                        .iter = DenseStorage.Iterator.init(&archetype.storage),
                        .last_run = last_run,
                        .current_run = current_run,
                    };
                }
                pub fn peek(self: *@This()) ?struct { Entity, Tuple } {
                    const old_iter = self.iter;
                    defer self.iter = old_iter;
                    return self.nextWithoutMarkingChange();
                }
                pub fn next(self: *@This()) ?struct { Entity, Tuple } {
                    return self.nextInner(true);
                }
                pub fn nextWithoutMarkingChange(self: *@This()) ?struct { Entity, Tuple } {
                    return self.nextInner(false);
                }
                fn nextInner(self: *@This(), comptime mark_change: bool) ?struct { Entity, Tuple } {
                    if (self.nextValidEntity()) |iter_result| {
                        const storage, const index = iter_result;
                        // SAFETY: immediatly filled in the following lines
                        var tuple: Tuple = undefined;
                        const entt = storage.getConst(Entity, index);
                        inline for (ReturnTypes, 0..) |Type, i| {
                            if (comptime Type == Entity) {
                                tuple[i] = entt;
                            } else {
                                tuple[i] = self.getComponent(Type, iter_result, mark_change);
                            }
                        }
                        return .{ entt, tuple };
                    }
                    return null;
                }
                /// iterate until we get a valid entity, or return null
                fn nextValidEntity(self: *@This()) ?StorageAddress {
                    while (self.iter.next()) |iter_result| {
                        if (self.hasValidTicks(iter_result)) {
                            return iter_result;
                        }
                    }
                    return null;
                }
                inline fn hasValidTicks(self: *@This(), storage_address: StorageAddress) bool {
                    inline for (Added) |Type| {
                        const tid = comptime Components.hash(Type);
                        const added_tick = storage_address[0].getAddedArray(tid)[storage_address[1]];
                        if (added_tick < self.last_run) return false;
                    }
                    inline for (Changed) |Type| {
                        if (comptime @sizeOf(Type) != 0) {
                            const tid = comptime Components.hash(Type);
                            const changed_tick = storage_address[0].getChangedArray(tid)[storage_address[1]];
                            if (changed_tick < self.last_run) return false;
                        }
                    }
                    return true;
                }
                fn getComponent(
                    self: *@This(),
                    comptime Type: type,
                    storage_address: StorageAddress,
                    comptime mark_change: bool,
                ) Type {
                    const CanonicalType = comptime Components.getCanonicalType(Type);
                    const access_type = comptime Components.getAccessType(Type);
                    if (comptime @sizeOf(CanonicalType) == 0) {
                        @compileError("Cannot get access to zero size component " ++ @typeName(CanonicalType));
                    }
                    const return_value: Type = switch (comptime access_type) {
                        .Const => storage_address[0].getConst(CanonicalType, storage_address[1]),
                        .PointerConst => @ptrCast(storage_address[0].getConst(CanonicalType, storage_address[1])),
                        .PointerMut => storage_address[0].get(CanonicalType, storage_address[1]),
                        .OptionalConst => storage_address[0].getConst(CanonicalType, storage_address[1]),
                        .OptionalPointerMut => storage_address[0].get(CanonicalType, storage_address[1]),
                        .OptionalPointerConst => @ptrCast(storage_address[0].getConst(CanonicalType, storage_address[1])),
                    };
                    if (comptime (mark_change and Components.hasChangedMetadata(CanonicalType))) {
                        if (comptime (access_type == .PointerMut)) {
                            const tid = Components.hash(CanonicalType);
                            storage_address[0].getChangedArray(tid)[storage_address[1]] = self.current_run;
                        } else if (comptime (access_type == .OptionalPointerMut)) {
                            if (return_value != null) {
                                const tid = Components.hash(CanonicalType);
                                storage_address[0].getChangedArray(tid)[storage_address[1]] = self.current_run;
                            }
                        }
                    }
                    return return_value;
                }
            };
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
        .Entity = entity.EntityTypeFactory(.medium),
        .Components = Components,
    });
    var archetype = try ArchetypeType.init(std.testing.allocator, Components.init(&.{ typeA, typeC, typeE }));
    defer archetype.deinit();

    try std.testing.expect(archetype.has(typeA));
    // can't add this line! (typeB isn't a component, so we get a compile time error!)
    // try std.testing.expect(!archetype.has(typeB));
    try std.testing.expect(archetype.has(typeC));
    try std.testing.expect(!archetype.has(typeD));
    try std.testing.expect(archetype.has(typeE));
}
