const std = @import("std");
const entity = @import("entity.zig");
const components = @import("components.zig");
const Tick = @import("types.zig").Tick;
const chunks = @import("chunks.zig");
const RegistryFactory = @import("registry.zig").Registry;

pub const ArchetypeOptions = struct {
    Components: type,
    Entity: type,
};

/// use ArchetypeOptions as options
pub fn Archetype(comptime options: ArchetypeOptions) type {
    return struct {
        const Self = @This();
        const ComponentTypeId = options.Components.ComponentTypeId;
        const Components = options.Components;
        const Entity = options.Entity;
        pub const Registry = RegistryFactory(.{
            .Components = Components,
            .Entity = Entity,
        });
        const EntityLocation = Registry.EntityLocation;
        pub const Chunks = chunks.ChunksFactory(.{
            .Entity = Entity,
            .Components = Components,
        });
        pub const Chunk = Chunks.Chunk;
        signature: Components,
        chunks: Chunks,
        allocator: std.mem.Allocator,

        inline fn hash(tid_or_component: anytype) ComponentTypeId {
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                return tid_or_component;
            } else if (comptime Components.isComponent(tid_or_component)) {
                return Components.hash(tid_or_component);
            }
        }

        pub fn init(alloc: std.mem.Allocator, sig: Components) !@This() {
            return .{
                .chunks = try Chunks.init(sig, alloc),
                .signature = sig,
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.chunks.deinit();
        }

        pub inline fn len(self: *@This()) usize {
            return self.chunks.len();
        }

        pub inline fn has(self: *@This(), tid_or_component: anytype) bool {
            return self.signature.has(tid_or_component);
        }

        pub fn reserve(self: *@This(), entt: Entity) !struct { *Chunk, usize } {
            return self.chunks.reserve(entt);
        }

        /// move entity to new archetype.
        /// this function only copies the values from component that exist in both archetypes.
        /// components only present in 'new_arch' must be set after this call.
        pub fn moveTo(self: *@This(), entt: Entity, location: *EntityLocation, new_arch: *@This(), current_tick: Tick, removed_logs: anytype) !struct { Entity, usize } {
            const new_chunk, const new_index = try new_arch.reserve(entt);

            var old_iter_type_id = self.signature.iterator();
            var type_index: usize = 0;
            while (old_iter_type_id.nextTypeId()) |tid| {
                const is_zst = Components.getSize(tid) == 0;
                if (new_arch.signature.has(tid)) {
                    if (!is_zst) {
                        const old_addr = location.chunk.getElemWithTypeIndex(type_index, @intCast(location.slot_index));
                        const new_chunk_type_index = new_chunk.getTypeIndex(tid);
                        const new_addr = new_chunk.getElemWithTypeIndex(new_chunk_type_index, new_index);
                        @memcpy(new_addr, old_addr);
                    }
                } else {
                    try removed_logs.addRemoved(tid, entt, current_tick);
                }
                if (!is_zst) {
                    type_index += 1;
                }
            }
            var new_iter_type_id = new_arch.signature.iterator();
            type_index = 0;
            while (new_iter_type_id.nextTypeIdNonEmpty()) |tid| {
                if (self.signature.has(tid)) {
                    const old_type_index = location.chunk.getTypeIndex(tid);
                    new_chunk.getMetadataArray(type_index, .Added)[new_index] = location.chunk.getMetadataArray(old_type_index, .Added)[@intCast(location.slot_index)];
                    new_chunk.getMetadataArray(type_index, .Changed)[new_index] = location.chunk.getMetadataArray(old_type_index, .Changed)[@intCast(location.slot_index)];
                } else {
                    new_chunk.getMetadataArray(type_index, .Changed)[new_index] = current_tick;
                    new_chunk.getMetadataArray(type_index, .Added)[new_index] = current_tick;
                }
                type_index += 1;
            }
            const removed_result = location.chunk.remove(@intCast(location.slot_index));
            location.slot_index = @intCast(new_index);
            location.chunk = new_chunk;
            location.arch = new_arch;
            return removed_result;
        }

        pub fn iterator(self: *@This(), comptime ReturnTypes: []const type, comptime Added: []const type, comptime Changed: []const type, last_run: Tick, current_run: Tick) Iterator(ReturnTypes, Added, Changed) {
            return Iterator(ReturnTypes, Added, Changed).init(self, last_run, current_run);
        }

        pub fn Iterator(comptime ReturnTypes: []const type, comptime Added: []const type, comptime Changed: []const type) type {
            for (ReturnTypes) |Type| {
                if (@sizeOf(Type) == 0) {
                    @compileError("Can't iterate over zero sized component array");
                }
            }
            const Tuple = std.meta.Tuple(ReturnTypes);
            return struct {
                last_run: Tick,
                current_run: Tick,
                iter: Chunks.Iterator,
                pub fn init(archtype: *Self, last_run: Tick, current_run: Tick) @This() {
                    return .{
                        .iter = Chunks.Iterator.init(&archtype.chunks),
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
                        const tid = chunk.getTypeIndex(Type);
                        const added_tick = chunk.getMetadataArray(tid, .Added)[slot_index];
                        if (added_tick < self.last_run) return false;
                    }
                    inline for (Changed) |Type| {
                        const tid = chunk.getTypeIndex(Type);
                        const changed_tick = chunk.getMetadataArray(tid, .Changed)[slot_index];
                        if (changed_tick < self.last_run) return false;
                    }
                    return true;
                }
                fn getComponent(self: *@This(), comptime Type: type, chunk: *Chunk, slot_index: usize, comptime mark_change: bool) Type {
                    const CanonicalType = comptime Components.getCanonicalType(Type);
                    const access_type = comptime Components.getAccessType(Type);
                    const return_value: Type = switch (comptime access_type) {
                        .Const => chunk.getConst(CanonicalType, slot_index),
                        .PointerConst => @ptrCast(chunk.getConst(CanonicalType, slot_index)),
                        .PointerMut => chunk.get(CanonicalType, slot_index),
                        .OptionalConst => chunk.getConst(CanonicalType, slot_index),
                        .OptionalPointerMut => chunk.get(CanonicalType, slot_index),
                        .OptionalPointerConst => @ptrCast(chunk.getConst(CanonicalType, slot_index)),
                    };
                    if (comptime mark_change) {
                        if (comptime (access_type == .PointerMut)) {
                            const tid = chunk.getTypeIndex(CanonicalType);
                            chunk.getMetadataArray(tid, .Changed)[slot_index] = self.current_run;
                        } else if (comptime (access_type == .OptionalPointerMut)) {
                            if (return_value != null) {
                                const tid = chunk.getTypeIndex(CanonicalType);
                                chunk.getMetadataArray(tid, .Changed)[slot_index] = self.current_run;
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
