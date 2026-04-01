const disjoint_sparseset = @import("disjoint_sparseset.zig");
const types = @import("../../types.zig");

pub const ComponentSparseSetOptions = struct {
    PageSize: usize = 4096,
    Component: type,
    Components: type,
    Entity: type,
};

fn createComponentValuesLayout(comptime Components: type, comptime Component: type) []const disjoint_sparseset.ValueType {
    var values: []const disjoint_sparseset.ValueType = &.{};

    if (@sizeOf(Component) != 0) {
        values = values ++ .{
            disjoint_sparseset.ValueType{
                .name = "data",
                .T = Component,
            },
        };
    }

    if (Components.hasAddedMetadata(Component)) {
        values = values ++ .{
            disjoint_sparseset.ValueType{
                .name = "added",
                .T = types.Tick,
            },
        };
    }

    if (Components.hasChangedMetadata(Component)) {
        values = values ++ .{
            disjoint_sparseset.ValueType{
                .name = "changed",
                .T = types.Tick,
            },
        };
    }

    return values;
}

pub fn ComponentSparseSet(comptime options: ComponentSparseSetOptions) type {
    return disjoint_sparseset.DisjointSparseSet(.{
        .K = options.Entity.Index,
        .PageSize = options.PageSize,
        .Vs = createComponentValuesLayout(options.Components, options.Component),
    });
}
