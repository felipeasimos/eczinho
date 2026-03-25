const std = @import("std");
const DisjointSparseSet = @import("disjoint_sparseset.zig").DisjointSparseSet;
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
        const Type = DisjointSparseSet(.{
            .K = options.Entity.Index,
            .V = options.Components.getType(tid),
            .PageSize = options.PageSize,
        });
        field_types[i] = Type;
        i += 1;
    }
    return @Tuple(&field_types);
}

pub fn SparseSets(comptime options: SparseSetsOptions) type {
    const sparse_components = options.Components
        .initFull()
        .applyStorageTypeMask(.Sparse);
    const ComponentArrays = CreateComponentArraysTupleType(options, sparse_components);
    const ComponentArraysLen = @typeInfo(ComponentArrays).@"struct".fields.len;

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

        fn getSparseSetIndex(comptime Component: type) usize {
            for (0..ComponentArraysLen) |i| {
                const TupleType = @typeInfo(ComponentArrays).@"struct".fields[i].type;
                if (TupleType.V == Component) {
                    return i;
                }
            }
            @compileError("Shouldn't reach this code line during comptime: Component is not sparse");
        }
        fn GetSparseSetResultType(comptime Component: type) type {
            const index = getSparseSetIndex(Component);
            return @typeInfo(ComponentArrays).@"struct".fields[index].type;
        }
        fn getSparseSet(self: *@This(), comptime Component: type) *GetSparseSetResultType(Component) {
            const index = comptime getSparseSetIndex(Component);
            return &self.sparse_sets[index];
        }
        pub fn add(self: *@This(), allocator: std.mem.Allocator, entt: Entity, value: anytype) !void {
            const sparse_set = self.getSparseSet(@TypeOf(value));
            std.debug.assert(!sparse_set.contains(entt.index));
            try sparse_set.add(allocator, entt.index, value);
        }
        pub fn contains(self: *@This(), entt: Entity, comptime Component: type) bool {
            const sparse_set = self.getSparseSet(Component);
            return sparse_set.contains(entt.index);
        }
        pub fn remove(self: *@This(), entt: Entity, comptime Component: type) void {
            const sparse_set = self.getSparseSet(Component);
            std.debug.assert(sparse_set.contains(entt.index));
            _ = sparse_set.remove(entt.index);
        }
        pub fn get(self: *@This(), entt: Entity, comptime Component: type) *Component {
            const sparse_set = self.getSparseSet(Component);
            std.debug.assert(sparse_set.contains(entt.index));
            return sparse_set.get(entt.index);
        }
        pub fn getConst(self: *@This(), entt: Entity, comptime Component: type) Component {
            const sparse_set = self.getSparseSet(Component);
            std.debug.assert(sparse_set.contains(entt.index));
            return sparse_set.getConst(entt.index);
        }
    };
}
