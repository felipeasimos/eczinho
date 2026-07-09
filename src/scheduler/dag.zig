const query = @import("../query/query.zig");
const entity = @import("../entity/entity.zig");
const event = @import("../event/event.zig");
const constraint = @import("../constraint/constraint.zig");
const system = @import("../system/system.zig");

const AccessType = struct {
    read: bool,
    write: bool,
};

fn generateComponentMatrix(systems: []const type, Components: type) [Components.Len][systems.len]AccessType {
    var matrix: [Components.Len][systems.len]AccessType = .{.{AccessType{ .read = false, .write = false }} **
        systems.len} **
        Components.Len;
    for (systems, 0..) |sys, system_index| {
        for (sys.ParamsSlice) |ParamType| {
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
                        .Const,
                        .PointerConst,
                        .OptionalConst,
                        .OptionalPointerConst,
                        => matrix[component_index][system_index].read = true,
                        .PointerMut, .OptionalPointerMut => matrix[component_index][system_index].write = true,
                    }
                }
            }
        }
    }
    return matrix;
}

fn generateResourceMatrix(systems: []const type, Resources: type) [Resources.Len][systems.len]AccessType {
    var matrix: [Resources.Len][systems.len]AccessType = .{.{AccessType{ .read = false, .write = false }} **
        systems.len} **
        Resources.Len;
    for (systems, 0..) |sys, system_index| {
        for (sys.ParamsSlice) |ParamType| {
            const T = ParamType.type.?;
            if (Resources.isResource(T)) {
                const Resource = Resources.getCanonicalType(T);
                const resource_index = Resources.getIndex(Resource);
                const access_type = Resources.getAccessType(T);
                switch (access_type) {
                    .Const,
                    .PointerConst,
                    .OptionalConst,
                    .OptionalPointerConst,
                    => matrix[resource_index][system_index].read = true,
                    .PointerMut, .OptionalPointerMut => matrix[resource_index][system_index].write = true,
                }
            }
        }
    }
    return matrix;
}

fn generateEventMatrix(systems: []const type, Events: type) [Events.Len][systems.len]AccessType {
    var matrix: [Events.Len][systems.len]AccessType = .{.{AccessType{ .read = false, .write = false }} **
        systems.len} **
        Events.Len;
    for (systems, 0..) |sys, system_index| {
        for (sys.ParamsSlice) |ParamType| {
            const T = ParamType.type.?;
            if (event.isEventReader(T) or event.isEventWriter(T)) {
                const Event = T.T;
                const event_index = Events.getIndex(Event);
                if (event.isEventReader(T)) {
                    matrix[event_index][system_index].read = true;
                } else {
                    matrix[event_index][system_index].write = true;
                }
            }
        }
    }
    return matrix;
}

fn getSystemIndex(comptime systems: []const type, sys: type) ?usize {
    inline for (systems, 0..) |s, i| {
        if (comptime system.isSameSystem(s, sys)) {
            return i;
        }
    }
    return null;
}

/// lower triangle matrix with dependencies
/// [i][j] = true -> i depends on j
fn generateDependencyMatrix(systems: []const type, constraints: []const constraint.Constraint) [systems.len][systems.len]bool {
    var matrix: [systems.len][systems.len]bool = .{.{false} **
        systems.len} **
        systems.len;
    for (constraints) |constr| {
        switch (constr) {
            .system => |sys_constr| switch (sys_constr.constraint) {
                .comes_after => |sys| {
                    if (comptime getSystemIndex(systems, sys_constr.system)) |before| {
                        if (comptime getSystemIndex(systems, sys)) |after| {
                            matrix[after][before] = true;
                        }
                    }
                },
                else => {},
            },
            else => {},
        }
    }
    return matrix;
}

fn hasWriteWriteConflict(matrix: anytype, i: usize, j: usize) bool {
    const num_rows = @typeInfo(@TypeOf(matrix)).array.len;
    inline for (0..num_rows) |row_idx| {
        const i_access = matrix[row_idx][i];
        const j_access = matrix[row_idx][j];
        if (i_access.write and j_access.write) return true;
    }
    return false;
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

fn SystemsSubSlice(comptime systems: []const type, comptime system_indices: []const usize) []const type {
    var systems_subslice: []const type = &.{};
    inline for (system_indices) |idx| {
        systems_subslice = systems_subslice ++ .{systems[idx]};
    }
    return systems_subslice;
}

fn getIndegree(dependency_matrix: anytype) [@typeInfo(@TypeOf(dependency_matrix)).array.len]usize {
    const side = @typeInfo(@TypeOf(dependency_matrix)).array.len;
    var indegree: [side]usize = .{0} ** side;
    // 1. compute indegree of every node
    for (0..side) |i| {
        for (0..side) |j| {
            // check if j -> i
            if (dependency_matrix[i][j]) {
                indegree[i] += 1;
            }
        }
    }
    return indegree;
}

fn topologicalSort(comptime systems: []const type, comptime dependency_matrix: anytype) [systems.len]usize {
    var order: [systems.len]usize = undefined;
    var out: usize = 0;
    var indegree: [systems.len]usize = getIndegree(dependency_matrix);

    // hold index of next system to visit
    var queue: [systems.len]usize = undefined;
    var qhead: usize = 0;
    var qtail: usize = 0;

    // 2. use a queue (breath first search). add indgree == 0 nodes to it first
    for (systems, 0..) |_, i| {
        if (indegree[i] == 0) {
            queue[qtail] = i;
            qtail += 1;
        }
    }

    // 3. iterate over queue, adding unvisited nodes to it
    while (qtail > qhead) {
        // pop from queu
        const u = queue[qhead];
        qhead += 1;

        order[out] = u;
        out += 1;

        // look for connections, push them to queue
        for (systems, 0..) |_, v| {
            // check if u -> v
            if (dependency_matrix[v][u]) {
                indegree[v] -= 1;
                if (indegree[v] == 0) {
                    queue[qtail] = v;
                    qtail += 1;
                }
            }
        }
    }
    if (out != systems.len) {
        @compileLog("Dependency graph contains a cycle");
    }
    return order;
}

fn GenerateParallelGroups(
    component_matrix: anytype,
    resource_matrix: anytype,
    event_matrix: anytype,
    dependency_matrix: anytype,
    systems: []const type,
    num_threads: usize,
) []const type {
    var visited: [systems.len]bool = .{false} ** systems.len;
    var current_parallel_group_idx = 0;
    var parallel_groups: []const type = &.{};

    const system_topo_order = topologicalSort(systems, dependency_matrix);
    // keep track of which nodes had their dependecies satisfied
    var indegree = getIndegree(dependency_matrix);

    outer: inline for (system_topo_order, 0..) |i, idx| {
        if (comptime indegree[i] != 0) {
            @compileError("Error when generating comptime DAG: system dependencies not ordered before it");
        }
        if (visited[i]) continue :outer;
        visited[i] = true;

        var parallel_indices: []const usize = &.{i};
        inner: inline for (system_topo_order[idx + 1 ..]) |j| {
            if (visited[j]) continue :inner;
            if (parallel_indices.len >= num_threads) break :inner;
            if (indegree[j] != 0) break :inner;
            if (hasConflict(component_matrix, i, j)) continue :inner;
            if (hasConflict(resource_matrix, i, j)) continue :inner;
            if (hasWriteWriteConflict(event_matrix, i, j)) continue :inner;

            visited[j] = true;
            // remove this dependency
            // [k][j] (j -> k)
            for (0..systems.len) |k| {
                if (dependency_matrix[k][j]) {
                    indegree[k] -= 1;
                }
            }
            parallel_indices = parallel_indices ++ .{j};
        }
        // remove this dependency
        // [k][i] (i -> k)
        for (0..systems.len) |k| {
            if (dependency_matrix[k][i]) {
                indegree[k] -= 1;
            }
        }
        current_parallel_group_idx += 1;
        parallel_groups = parallel_groups ++ .{ParallelGroup(SystemsSubSlice(systems, parallel_indices))};
    }
    for (0..systems.len) |k| {
        if (indegree[k] != 0) {
            @compileError("Error when building comptime schedule");
        }
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
pub fn DAG(
    comptime systems: []const type,
    comptime Components: type,
    comptime Resources: type,
    comptime Events: type,
    comptime num_threads: usize,
    comptime constraints: []const constraint.Constraint,
) type {
    @setEvalBranchQuota(1000000);
    const parallel_groups: []const type = parallel_groups: {
        if (comptime systems.len == 0) {
            break :parallel_groups &.{};
        }
        const component_matrix: [Components.Len][systems.len]AccessType = generateComponentMatrix(systems, Components);
        const resource_matrix: [Resources.Len][systems.len]AccessType = generateResourceMatrix(systems, Resources);
        const event_matrix: [Events.Len][systems.len]AccessType = generateEventMatrix(systems, Events);
        const dependency_matrix: [systems.len][systems.len]bool = generateDependencyMatrix(systems, constraints);
        break :parallel_groups GenerateParallelGroups(
            component_matrix,
            resource_matrix,
            event_matrix,
            dependency_matrix,
            systems,
            num_threads,
        );
    };
    return struct {
        pub const ParallelGroups = parallel_groups;
    };
}
