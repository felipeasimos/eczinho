const std = @import("std");
const entity = @import("entity/entity.zig");
const components = @import("components.zig");
const Tick = @import("types.zig").Tick;
const WorldFactory = @import("world.zig").World;
const dense_storage = @import("storage/dense_storage.zig");

pub const ArchetypeOptions = struct {
    Components: type,
    Entity: type,
};

/// use ArchetypeOptions as options
pub fn Archetype(comptime options: ArchetypeOptions) type {
    return struct {
        const Self = @This();
        pub const ComponentTypeId = options.Components.ComponentTypeId;
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const World = WorldFactory(.{
            .Components = Components,
            .Entity = Entity,
        });
        pub const EntityLocation = World.EntityLocation;
        pub const DenseStorage = dense_storage.DenseStorage(.{
            .World = World,
            .Config = dense_storage.DenseStorageConfig{
                .Chunks = dense_storage.chunks.ChunkOptions{
                    .Entity = Entity,
                    .EntityLocation = EntityLocation,
                    .Components = Components,
                },
            },
        });
        pub const Chunk = DenseStorage.Chunk;

        /// only contains components that both belong to this archetype AND have dense storage set
        signature: Components,
        storage: DenseStorage,

        inline fn hash(tid_or_component: anytype) ComponentTypeId {
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                return tid_or_component;
            } else if (comptime Components.isComponent(tid_or_component)) {
                return Components.hash(tid_or_component);
            }
        }

        pub fn init(alloc: std.mem.Allocator, sig: Components) !@This() {
            return .{
                .storage = try DenseStorage.init(alloc, sig),
                .signature = sig,
            };
        }

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            self.storage.deinit(alloc);
        }

        /// return the number of entities in the archetype
        pub inline fn len(self: *@This()) usize {
            return self.storage.len();
        }

        pub inline fn has(self: *@This(), tid_or_component: anytype) bool {
            return self.signature.has(tid_or_component);
        }

        pub fn reserve(self: *@This(), allocator: std.mem.Allocator, entt: Entity) !DenseStorage.ReserveResult {
            return self.storage.reserve(allocator, entt);
        }

        /// move entity to new archetype.
        /// this function only copies the values from dense components that exist in both archetypes.
        /// dense components only present in 'new_arch' must be set after this call.
        /// no move happens if the only difference between the two archetypes is sparse components
        pub fn moveTo(
            self: *@This(),
            allocator: std.mem.Allocator,
            entt: Entity,
            location: *EntityLocation,
            new_arch: *@This(),
            current_tick: Tick,
            removed_logs: anytype,
        ) !?struct { Entity, usize } {
            const new_chunk, const new_slot_index = try new_arch.reserve(allocator, entt);

            const old_dense_signature = self.signature.applyStorageTypeMask(.Dense);
            const new_dense_signature = new_arch.signature.applyStorageTypeMask(.Dense);

            // both archetypes have the non empty component -> just copy it
            {
                var intersection = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyNonEmptyMask();
                var iter_intersection = intersection.iterator();
                while (iter_intersection.nextTypeId()) |tid| {
                    const old_type_index = location.chunk.getNonEmptyTypeIndex(tid);
                    const old_addr = location
                        .chunk
                        .getElemWithTypeIndex(old_type_index, @intCast(location.dense_index));
                    const new_chunk_type_index = new_chunk.getNonEmptyTypeIndex(tid);
                    const new_addr = new_chunk.getElemWithTypeIndex(new_chunk_type_index, new_slot_index);
                    @memcpy(new_addr, old_addr);
                }
            }
            // removed components -> add to removed logs
            {
                var removed = old_dense_signature
                    .difference(new_dense_signature);
                var iter_removed = removed.iterator();
                while (iter_removed.nextTypeId()) |tid| {
                    try removed_logs.addRemoved(tid, entt, current_tick);
                }
            }
            // already existing zst components with added metadata -> copy metadta
            {
                var existing_zst_with_added = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyEmptyMask()
                    .applyAddedMask();
                var iter = existing_zst_with_added.iterator();
                while (iter.nextTypeId()) |tid| {
                    const old_type_index = location.chunk.getZSTIndex(tid);
                    const new_type_index = new_chunk.getZSTIndex(tid);
                    new_chunk
                        .getZSTMetadataArray(new_type_index)[new_slot_index] = location
                        .chunk
                        .getZSTMetadataArray(old_type_index)[@intCast(location.dense_index)];
                }
            }
            // already existing non empty components with added metadata -> copy metadata
            {
                var existing_with_added = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyNonEmptyMask()
                    .applyAddedMask();
                var iter = existing_with_added.iterator();
                while (iter.nextTypeId()) |tid| {
                    const old_type_index = location.chunk.getNonEmptyTypeIndex(tid);
                    const new_type_index = new_chunk.getNonEmptyTypeIndex(tid);
                    new_chunk
                        .getNonEmptyMetadataArray(new_type_index, .Added)[new_slot_index] = location
                        .chunk
                        .getNonEmptyMetadataArray(old_type_index, .Added)[@intCast(location.dense_index)];
                }
            }
            // already existing non empty components with changed metadata -> copy metadata
            {
                var existing_with_changed = old_dense_signature
                    .intersection(new_dense_signature)
                    .applyNonEmptyMask()
                    .applyChangedMask();
                var iter = existing_with_changed.iterator();
                while (iter.nextTypeId()) |tid| {
                    const old_type_index = location.chunk.getNonEmptyTypeIndex(tid);
                    const new_type_index = new_chunk.getNonEmptyTypeIndex(tid);
                    new_chunk
                        .getNonEmptyMetadataArray(new_type_index, .Changed)[new_slot_index] = location
                        .chunk
                        .getNonEmptyMetadataArray(old_type_index, .Changed)[@intCast(location.dense_index)];
                }
            }
            // newly added zst component with added metadata -> update metadata
            {
                var newly_added_zst = new_dense_signature
                    .difference(old_dense_signature)
                    .applyEmptyMask()
                    .applyAddedMask();
                var iter = newly_added_zst.iterator();
                while (iter.nextTypeId()) |tid| {
                    const new_type_index = new_chunk.getZSTIndex(tid);
                    new_chunk.getZSTMetadataArray(new_type_index)[new_slot_index] = current_tick;
                }
            }
            // newly added non-empty component with added metadata -> update metadata
            {
                var newly_added_non_empty = new_dense_signature
                    .difference(old_dense_signature)
                    .applyNonEmptyMask()
                    .applyAddedMask();
                var iter = newly_added_non_empty.iterator();
                while (iter.nextTypeId()) |tid| {
                    const new_type_index = new_chunk.getNonEmptyTypeIndex(tid);
                    new_chunk.getNonEmptyMetadataArray(new_type_index, .Added)[new_slot_index] = current_tick;
                }
            }
            // newly added non-empty component with changed metadata -> update metadata
            {
                var newly_added_non_empty = new_dense_signature
                    .difference(old_dense_signature)
                    .applyNonEmptyMask()
                    .applyChangedMask();
                var iter = newly_added_non_empty.iterator();
                while (iter.nextTypeId()) |tid| {
                    const new_type_index = new_chunk.getNonEmptyTypeIndex(tid);
                    new_chunk.getNonEmptyMetadataArray(new_type_index, .Changed)[new_slot_index] = current_tick;
                }
            }
            const removed_result = location.chunk.remove(allocator, @intCast(location.dense_index));
            location.dense_index = @intCast(new_slot_index);
            location.chunk = new_chunk;
            location.arch = new_arch;
            return removed_result;
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
            const Tuple = std.meta.Tuple(ReturnTypes);
            return struct {
                last_run: Tick,
                current_run: Tick,
                iter: DenseStorage.Iterator,
                pub fn init(archetype: *Self, last_run: Tick, current_run: Tick) @This() {
                    return .{
                        .iter = DenseStorage.Iterator.init(&archetype.storage.storage),
                        .last_run = last_run,
                        .current_run = current_run,
                    };
                }
                pub fn peek(self: *@This()) ?Tuple {
                    const old_iter = self.iter;
                    defer self.iter = old_iter;
                    return self.nextWithoutMarkingChange();
                }
                pub fn next(self: *@This()) ?Tuple {
                    return self.nextInner(true);
                }
                pub fn nextWithoutMarkingChange(self: *@This()) ?Tuple {
                    return self.nextInner(false);
                }
                fn nextInner(self: *@This(), comptime mark_change: bool) ?Tuple {
                    if (self.nextValidEntity()) |iter_result| {
                        const chunk, const slot_index = iter_result;
                        // SAFETY: immediatly filled in the following lines
                        var tuple: std.meta.Tuple(ReturnTypes) = undefined;
                        inline for (ReturnTypes, 0..) |Type, i| {
                            if (comptime Type == Entity) {
                                tuple[i] = chunk.getConst(Entity, slot_index);
                            } else {
                                tuple[i] = self.getComponent(Type, chunk, slot_index, mark_change);
                            }
                        }
                        return tuple;
                    }
                    return null;
                }
                /// iterate until we get a valid entity, or return null
                fn nextValidEntity(self: *@This()) ?struct { *Chunk, usize } {
                    while (self.iter.next()) |iter_result| {
                        const chunk, const slot_index = iter_result;
                        if (self.hasValidTicks(chunk, slot_index)) {
                            return .{ chunk, slot_index };
                        }
                    }
                    return null;
                }
                inline fn hasValidTicks(self: *@This(), chunk: *Chunk, slot_index: usize) bool {
                    inline for (Added) |Type| {
                        if (comptime @sizeOf(Type) != 0) {
                            const type_index = chunk.getNonEmptyTypeIndex(Type);
                            const added_tick = chunk.getNonEmptyMetadataArray(type_index, .Added)[slot_index];
                            if (added_tick < self.last_run) return false;
                        } else {
                            const type_index = chunk.getZSTIndex(Type);
                            const added_tick = chunk.getZSTMetadataArray(type_index)[slot_index];
                            if (added_tick < self.last_run) return false;
                        }
                    }
                    inline for (Changed) |Type| {
                        if (comptime @sizeOf(Type) != 0) {
                            const type_index = chunk.getNonEmptyTypeIndex(Type);
                            const changed_tick = chunk.getNonEmptyMetadataArray(type_index, .Changed)[slot_index];
                            if (changed_tick < self.last_run) return false;
                        }
                    }
                    return true;
                }
                fn getComponent(
                    self: *@This(),
                    comptime Type: type,
                    chunk: *Chunk,
                    slot_index: usize,
                    comptime mark_change: bool,
                ) Type {
                    const CanonicalType = comptime Components.getCanonicalType(Type);
                    const access_type = comptime Components.getAccessType(Type);
                    if (comptime @sizeOf(CanonicalType) == 0) {
                        @compileError("Cannot get access to zero size component " ++ @typeName(CanonicalType));
                    }
                    const return_value: Type = switch (comptime access_type) {
                        .Const => chunk.getConst(CanonicalType, slot_index),
                        .PointerConst => @ptrCast(chunk.getConst(CanonicalType, slot_index)),
                        .PointerMut => chunk.get(CanonicalType, slot_index),
                        .OptionalConst => chunk.getConst(CanonicalType, slot_index),
                        .OptionalPointerMut => chunk.get(CanonicalType, slot_index),
                        .OptionalPointerConst => @ptrCast(chunk.getConst(CanonicalType, slot_index)),
                    };
                    // ZSTs don't change, so we can ignore this for ZSTs
                    if (comptime mark_change) {
                        if (comptime (access_type == .PointerMut)) {
                            const tid = chunk.getNonEmptyTypeIndex(CanonicalType);
                            chunk.getNonEmptyMetadataArray(tid, .Changed)[slot_index] = self.current_run;
                        } else if (comptime (access_type == .OptionalPointerMut)) {
                            if (return_value != null) {
                                const tid = chunk.getNonEmptyTypeIndex(CanonicalType);
                                chunk.getNonEmptyMetadataArray(tid, .Changed)[slot_index] = self.current_run;
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
