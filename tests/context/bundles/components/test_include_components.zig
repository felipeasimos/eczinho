const eczinho = @import("eczinho");
const std = @import("std");

test "without non included components" {
    const ComponentA = struct { a: f32 };
    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = comptime eczinho.BundleContext.Builder.init()
        .build(Entity);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA) == null);
}

test "with given components" {
    const ComponentA = struct { a: f32 };
    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = comptime eczinho.BundleContext.Builder.init()
        .addComponent(ComponentA)
        .build(Entity);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA) != null);
}

test "with given components and specific configs" {
    const ComponentA = struct { a: f32 };
    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = comptime eczinho.BundleContext.Builder.init()
        .addComponentWithConfig(ComponentA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = true,
            },
        })
        .build(Entity);
    const component_index = comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA);
    try std.testing.expect(component_index != null);
    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.ComponentConfigs[component_index.?]);
}

test "include multiple components at once" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };

    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = comptime eczinho.BundleContext.Builder.init()
        .addComponents(&.{ ComponentA, ComponentB, ComponentC })
        .build(Entity);

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentC) != null);
}

test "include multiple components individually" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };

    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = comptime eczinho.BundleContext.Builder.init()
        .addComponent(ComponentA)
        .addComponent(ComponentB)
        .addComponent(ComponentC)
        .build(Entity);

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentC) != null);
}

test "include multiple components individually with specific configs" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };

    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = comptime eczinho.BundleContext.Builder.init()
        .addComponentWithConfig(ComponentA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = true,
            },
        })
        .addComponentWithConfig(ComponentB, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = true,
                .changed = false,
                .removed = true,
            },
        })
        .addComponentWithConfig(ComponentC, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = true,
                .removed = true,
            },
        })
        .build(Entity);

    const component_a_index = comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA);
    const component_b_index = comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentB);
    const component_c_index = comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentC);

    try std.testing.expect(component_a_index != null);
    try std.testing.expect(component_b_index != null);
    try std.testing.expect(component_c_index != null);

    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.ComponentConfigs[component_a_index.?]);

    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = true,
            .changed = false,
        },
    }, Context.ComponentConfigs[component_b_index.?]);

    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = true,
        },
    }, Context.ComponentConfigs[component_c_index.?]);
}

test "include components individually and at once" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };

    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = comptime eczinho.BundleContext.Builder.init()
        .addComponents(&.{ ComponentA, ComponentB })
        .addComponentWithConfig(ComponentC, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = true,
                .removed = true,
            },
        })
        .build(Entity);

    const component_a_index = comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA);
    const component_b_index = comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentB);
    const component_c_index = comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentC);

    try std.testing.expect(component_a_index != null);
    try std.testing.expect(component_b_index != null);
    try std.testing.expect(component_c_index != null);

    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = true,
        },
    }, Context.ComponentConfigs[component_c_index.?]);
}
