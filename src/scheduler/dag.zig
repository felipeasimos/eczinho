const query = @import("../query/query.zig");
const entity = @import("../entity/entity.zig");

const AccessType = struct {
    read: bool,
    write: bool,
};

fn generateComponentMatrix(systems: []const type, Components: type) [Components.Len][systems.len]AccessType {
    var matrix: [Components.Len][systems.len]AccessType = .{.{AccessType{ .read = false, .write = false }} ** systems.len} ** Components.Len;
    for (systems, 0..) |system, system_index| {
        for (system.ParamsSlice) |ParamType| {
            const param_type = ParamType.type.?;
            if (query.isQuery(param_type)) {
                const component_accesses = param_type.request.q;
                inner: for (component_accesses) |component_access| {
                    // we can't write to entities, so they are always in the "canonical" type
                    if (entity.isEntity(component_access)) continue :inner;
                    const Component = Components.getCanonicalType(component_access);
                    const component_index = Components.getIndex(Component);
                    const access_type = Components.getAccessType(component_access);
                    switch (access_type) {
                        .Const, .PointerConst, .OptionalConst, .OptionalPointerConst => matrix[component_index][system_index].read = true,
                        .PointerMut, .OptionalPointerMut => matrix[component_index][system_index].write = true,
                    }
                }
            }
        }
    }
    return matrix;
}

fn generateResourceMatrix(systems: []const type, Resources: type) [Resources.Len][systems.len]AccessType {
    var matrix: [Resources.Len][systems.len]AccessType = .{.{AccessType{ .read = false, .write = false }} ** systems.len} ** Resources.Len;
    for (systems, 0..) |system, system_index| {
        for (system.ParamsSlice) |ParamType| {
            if (Resources.isResource(ParamType.type.?)) {
                const Resource = Resources.getCanonicalType(ParamType);
                const component_index = Resources.getIndex(Resource);
                const access_type = Resources.getAccessType(ParamType);
                switch (access_type) {
                    .Const, .PointerConst, .OptionalConst, .OptionalPointerConst => matrix[component_index][system_index].read = true,
                    .PointerMut, .OptionalPointerMut => matrix[component_index][system_index].write = true,
                }
            }
        }
    }
    return matrix;
}

fn hasConflict(matrix: anytype, i: usize, j: usize) bool {
    const num_rows = @typeInfo(@TypeOf(matrix)).array.len;
    inline for (0..num_rows) |row_idx| {
        const i_access = matrix[row_idx][i];
        const j_access = matrix[row_idx][j];
        if (i_access.read and j_access.write) return true;
        if (i_access.write and j_access.write) return true;
        if (i_access.write and j_access.read) return true;
    }
    return false;
}

fn systemsSubSlice(comptime systems: []const type, comptime system_indices: []const usize) []const type {
    var systems_subslice: []const type = &.{};
    inline for (system_indices) |idx| {
        systems_subslice = systems_subslice ++ .{systems[idx]};
    }
    return systems_subslice;
}

fn generateParallelGroups(component_matrix: anytype, resource_matrix: anytype, systems: []const type, num_threads: usize) []const type {
    var visited: [systems.len]bool = .{false} ** systems.len;
    var parallel_groups: []const type = &.{};

    outer: inline for (systems, 0..) |_, i| {
        if (visited[i]) continue :outer;
        var parallel_indices: []const usize = &.{i};
        inner: inline for (systems[i + 1 ..], i + 1..) |_, j| {
            if (visited[i + 1]) continue :inner;
            if (parallel_indices.len > num_threads) break :inner;
            if (hasConflict(component_matrix, i, j)) continue :inner;
            if (hasConflict(resource_matrix, i, j)) continue :inner;
            visited[j] = true;
            parallel_indices = parallel_indices ++ .{j};
        }
        parallel_groups = parallel_groups ++ .{ParallelGroup(systemsSubSlice(systems, parallel_indices))};
    }
    return parallel_groups;
}

/// indices of systems that can will run in parallel
pub fn ParallelGroup(comptime systems: []const type) type {
    return struct {
        pub const Systems: []const type = systems;
    };
}

/// Dependency DAG
pub fn DAG(comptime systems: []const type, comptime Components: type, comptime Resources: type, comptime num_threads: usize) type {
    @setEvalBranchQuota(1000000);
    const component_matrix: [Components.Len][systems.len]AccessType = generateComponentMatrix(systems, Components);
    const resource_matrix: [Resources.Len][systems.len]AccessType = generateResourceMatrix(systems, Resources);
    const parallel_groups: []const type = generateParallelGroups(component_matrix, resource_matrix, systems, num_threads);
    return struct {
        pub const ParallelGroups = parallel_groups;
    };
}
