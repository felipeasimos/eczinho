const std = @import("std");
const ComponentSparseSet = @import("component_sparseset.zig").ComponentSparseSet;
const types = @import("../../types.zig");

pub const SparseSetsOptions = struct {
    Components: type,
    Entity: type,
    PageSize: usize,
};

fn CreateComponentArraysTupleType(
    comptime options: SparseSetsOptions,
    comptime sparse_components: options.Components,
) type {
    var field_types: [sparse_components.len()]type = undefined;
    var iter = comptime sparse_components.iterator();
    var i = 0;
    inline while (iter.nextTypeId()) |tid| {
        const Type = ComponentSparseSet(.{
            .Component = options.Components.getType(tid),
            .Components = options.Components,
            .Entity = options.Entity,
            .PageSize = options.PageSize,
        });
        field_types[i] = Type;
        i += 1;
    }
    return @Tuple(&field_types);
}

pub fn SparseSets(comptime options: SparseSetsOptions) type {
    const SparseComponents = options.Components
        .initFull()
        .applyStorageTypeMask(.Sparse);
    const ComponentArraysLen = SparseComponents.len();
    const ComponentArrays = CreateComponentArraysTupleType(options, SparseComponents);

    const EmptySets = EmptySets: {
        // SAFETY: filled immediatly after
        var sets: ComponentArrays = undefined;
        for (0..ComponentArraysLen) |i| {
            sets[i] = .empty;
        }
        break :EmptySets sets;
    };

    return struct {
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const empty: @This() = .{};
        sparse_sets: ComponentArrays = EmptySets,

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            inline for (0..ComponentArraysLen) |i| {
                self.sparse_sets[i].deinit(allocator);
            }
        }

        fn getSparseSetIndex(tid_or_component: anytype) usize {
            return SparseComponents.getIndexInSet(tid_or_component);
        }
        fn GetComponentFromSparseSetIndex(comptime index: usize) type {
            return Components.getType(Components.getIdFromIndex(SparseComponents.getGlobalIndex(index).?));
        }
        fn GetSparseSetResultType(comptime Component: type) type {
            const index = getSparseSetIndex(Component);
            return @typeInfo(ComponentArrays).@"struct".fields[index].type;
        }
        fn getSparseSet(self: *@This(), comptime Component: type) *GetSparseSetResultType(Component) {
            const index = comptime getSparseSetIndex(Component);
            return &self.sparse_sets[index];
        }
        pub fn reserve(self: *@This(), allocator: std.mem.Allocator, tid_or_component: anytype, entt: Entity) !void {
            if (comptime ComponentArraysLen == 0) return;
            switch (getSparseSetIndex(tid_or_component)) {
                else => @panic("invalid component type id for sparse set storage"),
                inline 0...(ComponentArraysLen - 1) => |sparse_set_index| {
                    const sparse_set = &self.sparse_sets[sparse_set_index];
                    std.debug.assert(!sparse_set.contains(entt.index));
                    try sparse_set.reserve(allocator, entt.index);
                },
            }
        }
        pub fn setMetadataToCurrentTick(
            self: *@This(),
            tid_or_component: anytype,
            entt: Entity,
            current_tick: types.Tick,
        ) void {
            if (comptime ComponentArraysLen == 0) return;
            switch (getSparseSetIndex(tid_or_component)) {
                else => @panic("invalid component type id for sparse set storage"),
                inline 0...(ComponentArraysLen - 1) => |sparse_set_index| {
                    const Component = GetComponentFromSparseSetIndex(sparse_set_index);
                    const sparse_set = &self.sparse_sets[sparse_set_index];
                    std.debug.assert(sparse_set.contains(entt.index));
                    if (comptime Components.hasAddedMetadata(Component)) {
                        self.getAdded(Component, entt).* = current_tick;
                    }
                    if (comptime Components.hasChangedMetadata(Component)) {
                        self.getChanged(Component, entt).* = current_tick;
                    }
                },
            }
        }
        pub inline fn contains(self: *@This(), comptime Component: type, entt: Entity, _: anytype) bool {
            const sparse_set = self.getSparseSet(Component);
            return sparse_set.contains(entt.index);
        }
        pub fn remove(
            self: *@This(),
            allocator: std.mem.Allocator,
            tid_or_component: anytype,
            entt: Entity,
            current_tick: types.Tick,
            removed_logs: anytype,
        ) !void {
            if (comptime ComponentArraysLen == 0) return;
            switch (getSparseSetIndex(tid_or_component)) {
                else => @panic("invalid component type id for sparse set storage"),
                inline 0...(ComponentArraysLen - 1) => |sparse_set_index| {
                    const sparse_set = &self.sparse_sets[sparse_set_index];
                    const Component = GetComponentFromSparseSetIndex(sparse_set_index);
                    std.debug.assert(sparse_set.contains(entt.index));
                    _ = sparse_set.remove(entt.index);
                    if (comptime Components.hasRemovedMetadata(Component)) {
                        try removed_logs.addRemoved(allocator, comptime Components.hash(Component), entt, current_tick);
                    }
                },
            }
        }
        pub fn get(self: *@This(), comptime Component: type, entt: Entity) *Component {
            const sparse_set = self.getSparseSet(Component);
            std.debug.assert(sparse_set.contains(entt.index));
            const ret = sparse_set.get(entt.index, "data");
            return ret;
        }
        pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {
            const sparse_set = self.getSparseSet(Component);
            std.debug.assert(sparse_set.contains(entt.index));
            return sparse_set.getConst(entt.index, "data");
        }
        pub fn getAdded(self: *@This(), comptime Component: type, entt: Entity) *types.Tick {
            const sparse_set = self.getSparseSet(Component);
            std.debug.assert(sparse_set.contains(entt.index));
            return sparse_set.get(entt.index, "added");
        }
        pub fn getChanged(self: *@This(), comptime Component: type, entt: Entity) *types.Tick {
            const sparse_set = self.getSparseSet(Component);
            std.debug.assert(sparse_set.contains(entt.index));
            return sparse_set.get(entt.index, "changed");
        }
        pub fn getAddedConst(self: *@This(), comptime Component: type, entt: Entity) types.Tick {
            const sparse_set = self.getSparseSet(Component);
            std.debug.assert(sparse_set.contains(entt.index));
            return sparse_set.getConst(entt.index, "added");
        }
        pub fn getChangedConst(self: *@This(), comptime Component: type, entt: Entity) types.Tick {
            const sparse_set = self.getSparseSet(Component);
            std.debug.assert(sparse_set.contains(entt.index));
            return sparse_set.getConst(entt.index, "changed");
        }
    };
}
