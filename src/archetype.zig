const std = @import("std");
const sparseset = @import("sparse_set.zig");
const entity = @import("entity.zig");
const components = @import("components.zig");
const array = @import("array.zig");
const Tick = @import("types.zig").Tick;
const registry = @import("registry.zig");

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
        const Registry = registry.Registry(.{
            .Components = Components,
            .Entity = Entity,
        });
        signature: Components,
        components: std.AutoHashMap(ComponentTypeId, array.Array),
        entities_to_component_index: sparseset.SparseSet(.{
            .T = Entity.Int,
            .PageMask = Entity.entity_mask,
        }),
        allocator: std.mem.Allocator,
        added: []std.ArrayList(Tick) = &.{},
        changed: []std.ArrayList(Tick) = &.{},

        inline fn hash(tid_or_component: anytype) ComponentTypeId {
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                return tid_or_component;
            } else if (comptime Components.isComponent(tid_or_component)) {
                return Components.hash(tid_or_component);
            }
        }

        /// creates the array if it doesn't exist. Uses type.
        inline fn tryGetComponentArray(self: *@This(), tid_or_component: anytype) !*array.Array {
            Components.checkSize(tid_or_component);
            const component_size = Components.getSize(tid_or_component);
            const component_alignment = Components.getAlignment(tid_or_component);
            const new_array = array.Array.init(component_size, component_alignment);
            const entry = try self.components.getOrPutValue(hash(tid_or_component), new_array);
            return entry.value_ptr;
        }

        /// returns null if the array doesn't exist. Uses type
        inline fn optGetComponentArray(self: *@This(), tid_or_component: anytype) ?*array.Array {
            Components.checkSize(tid_or_component);
            if (self.components.getEntry(hash(tid_or_component))) |entry| {
                return entry.value_ptr;
            }
            return null;
        }

        /// returns the array assuming that it exists. Uses type
        pub inline fn getComponentArray(self: *@This(), tid_or_component: anytype) *array.Array {
            Components.checkSize(tid_or_component);
            return self.components.getEntry(hash(tid_or_component)).?.value_ptr;
        }

        pub fn init(alloc: std.mem.Allocator, sig: Components) !@This() {
            const added = try alloc.alloc(std.ArrayList(Tick), sig.len());
            const changed = try alloc.alloc(std.ArrayList(Tick), sig.len());
            @memset(added, .empty);
            @memset(changed, .empty);
            return .{
                .added = added,
                .changed = changed,
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
            for (self.added, self.changed) |*added, *changed| {
                added.deinit(self.allocator);
                changed.deinit(self.allocator);
            }
            self.allocator.free(self.added);
            self.allocator.free(self.changed);
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
            Components.checkSize(Component);
            std.debug.assert(self.has(Component));
            std.debug.assert(self.valid(entt));

            const entt_index = self.entities_to_component_index.getDenseIndex(entt.toInt());
            const component_arr = self.getComponentArray(Component);
            return component_arr.getAs(Component, entt_index);
        }

        pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {
            Components.checkSize(Component);
            std.debug.assert(self.has(Component));
            std.debug.assert(self.valid(entt));

            const entt_index = self.entities_to_component_index.getDenseIndex(entt.toInt());
            const component_arr = self.getComponentArray(Component);
            return component_arr.getConst(Component, entt_index);
        }

        pub fn valid(self: *@This(), entt: Entity) bool {
            return self.entities_to_component_index.contains(entt.toInt());
        }

        pub fn reserve(self: *@This(), entt: Entity) !void {
            std.debug.assert(!self.valid(entt));

            var iter = self.signature.iterator();
            while (iter.nextTypeIdNonEmpty()) |tid| {
                const component_arr = try self.tryGetComponentArray(tid);
                try component_arr.reserve(self.allocator, 1);
            }
            try self.entities_to_component_index.add(entt.toInt());
            for (self.added, self.changed) |*added, *changed| {
                try added.append(self.allocator, 0);
                try changed.append(self.allocator, 0);
            }
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
            for (self.added, self.changed) |*added, *changed| {
                _ = added.swapRemove(entt_index);
                _ = changed.swapRemove(entt_index);
            }
        }

        pub fn getAddedArray(self: *@This(), tid_or_component: anytype) *std.ArrayList(Tick) {
            const index = self.signature.getIndexInSet(tid_or_component);
            return &self.added[index];
        }

        pub fn getChangedArray(self: *@This(), tid_or_component: anytype) *std.ArrayList(Tick) {
            const index = self.signature.getIndexInSet(tid_or_component);
            return &self.changed[index];
        }

        /// move entity to new archetype.
        /// this function only copies the values from component that exist in both archetypes.
        /// components only present in 'new_arch' must be set after this call.
        pub fn moveTo(self: *@This(), entt: Entity, new_arch: *@This(), reg: *Registry) !void {
            std.debug.assert(self.valid(entt));
            std.debug.assert(!new_arch.valid(entt));

            const old_entt_index = self.getEntityComponentIndex(entt);
            try new_arch.reserve(entt);
            const new_entt_index = new_arch.getEntityComponentIndex(entt);

            var old_iter_type_id = self.signature.iterator();
            while (old_iter_type_id.nextTypeId()) |tid| {
                if (new_arch.signature.has(tid)) {
                    if (Components.getSize(tid) != 0) {
                        const old_addr = self.getComponentArray(tid).get(old_entt_index);
                        const new_addr = new_arch.getComponentArray(tid).get(new_entt_index);
                        @memcpy(new_addr, old_addr);
                    }
                } else {
                    // component removed in new arch
                    try reg.addRemoved(tid, entt);
                }
            }
            var new_iter_type_id = new_arch.signature.iterator();
            while (new_iter_type_id.nextTypeId()) |tid| {
                if (self.signature.has(tid)) {
                    new_arch.getAddedArray(tid).items[new_entt_index] = self.getAddedArray(tid).items[old_entt_index];
                    new_arch.getChangedArray(tid).items[new_entt_index] = self.getChangedArray(tid).items[old_entt_index];
                } else {
                    const tick = reg.getTick();
                    new_arch.getAddedArray(tid).items[new_entt_index] = tick;
                    new_arch.getChangedArray(tid).items[new_entt_index] = tick;
                }
            }
            self.remove(entt);
        }

        pub fn iterator(self: *@This(), comptime ReturnTypes: []const type, comptime Added: []const type, comptime Changed: []const type, last_run: Tick) Iterator(ReturnTypes, Added, Changed) {
            return Iterator(ReturnTypes, Added, Changed).init(self, last_run);
        }

        pub fn Iterator(comptime ReturnTypes: []const type, comptime Added: []const type, comptime Changed: []const type) type {
            for (ReturnTypes) |Type| {
                if (@sizeOf(Type) == 0) {
                    @compileError("Can't iterate over zero sized component array");
                }
            }
            const Tuple = std.meta.Tuple(ReturnTypes);
            return struct {
                archetype: *Self,
                index: usize = 0,
                last_run: Tick,
                pub fn init(archtype: *Self, last_run: Tick) @This() {
                    return .{
                        .archetype = archtype,
                        .last_run = last_run,
                    };
                }
                fn getComponent(self: *@This(), comptime Type: type) Type {
                    const CanonicalType = comptime Components.getCanonicalType(Type);
                    const access_type = comptime Components.getAccessType(Type);
                    const comp_arr = self.archetype.getComponentArray(CanonicalType);
                    return switch (comptime access_type) {
                        .Const => comp_arr.getConst(CanonicalType, self.index),
                        .PointerConst => @ptrCast(comp_arr.getAs(CanonicalType, self.index)),
                        .PointerMut => comp_arr.getAs(CanonicalType, self.index),
                        .OptionalConst => comp_arr.getConst(CanonicalType, self.index),
                        .OptionalPointerMut => comp_arr.getAs(CanonicalType, self.index),
                        .OptionalPointerConst => @ptrCast(comp_arr.getAs(CanonicalType, self.index)),
                    };
                }
                fn hasValidTicks(self: *@This()) bool {
                    const entt_int = self.archetype.entities_to_component_index.items()[self.index];
                    inline for (Added) |Type| {
                        const added_tick = self.archetype.getAddedArray(Type).items[entt_int];
                        if (added_tick < self.last_run) return false;
                    }
                    inline for (Changed) |Type| {
                        const changed_tick = self.archetype.getChangedArray(Type).items[entt_int];
                        if (changed_tick < self.last_run) return false;
                    }
                    return true;
                }
                fn nextValidEntity(self: *@This()) ?Entity.Int {
                    if (self.index >= self.archetype.len()) {
                        return null;
                    }
                    while (!self.hasValidTicks()) {
                        self.index += 1;
                        if (self.index >= self.archetype.len()) return null;
                    }
                    return self.archetype.entities_to_component_index.items()[self.index];
                }
                pub fn next(self: *@This()) ?Tuple {
                    if (self.index >= self.archetype.len()) {
                        return null;
                    }
                    if (self.nextValidEntity()) |entt_int| {
                        // SAFETY: immediatly filled in the following lines
                        var tuple: std.meta.Tuple(ReturnTypes) = undefined;
                        inline for (ReturnTypes, 0..) |Type, i| {
                            if (comptime Type == Entity) {
                                tuple[i] = Entity.fromInt(entt_int);
                            } else {
                                tuple[i] = self.getComponent(Type);
                            }
                        }
                        return tuple;
                    }
                    return null;
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
