const eczinho = @import("eczinho");
const std = @import("std");

test "without non included components" {
    const ComponentA = struct { a: f32 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .build();
    try std.testing.expect(!Context.Components.isComponent(ComponentA));
}

test "with given components" {
    const ComponentA = struct { a: f32 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addComponent(ComponentA)
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
}

test "with given components with specific configs" {
    const ComponentA = struct { a: f32 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addComponentWithConfig(ComponentA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
        .build();
    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.Components.getConfig(ComponentA));
}

test "include multiple components at once" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addComponents(&.{ ComponentA, ComponentB, ComponentC })
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expect(Context.Components.isComponent(ComponentB));
    try std.testing.expect(Context.Components.isComponent(ComponentC));
}

test "include multiple components individually" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addComponent(ComponentA)
        .addComponent(ComponentB)
        .addComponent(ComponentC)
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expect(Context.Components.isComponent(ComponentB));
    try std.testing.expect(Context.Components.isComponent(ComponentC));
    try std.testing.expectEqual(3, Context.Components.Len);
}

test "include multiple components individually with specific configs" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addComponentWithConfig(ComponentA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
        .addComponentWithConfig(ComponentB, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
        .addComponentWithConfig(ComponentC, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
        .build();
    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.Components.getConfig(ComponentA));
    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.Components.getConfig(ComponentB));
    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.Components.getConfig(ComponentC));
    try std.testing.expectEqual(3, Context.Components.Len);
}

test "include components individually and at once, with specific configs" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addComponents(&.{ ComponentA, ComponentB })
        .addComponentWithConfig(ComponentC, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expect(Context.Components.isComponent(ComponentB));
    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.Components.getConfig(ComponentC));
}

test "override config of component that was just added" {
    const ComponentA = struct { a: f32 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addComponent(ComponentA)
        .overrideComponentConfig(ComponentA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
        .build();
    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.Components.getConfig(ComponentA));
    try std.testing.expectEqual(1, Context.Components.ComponentConfigs.len);
}
