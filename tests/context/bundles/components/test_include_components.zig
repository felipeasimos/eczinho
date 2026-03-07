const eczinho = @import("eczinho");
const std = @import("std");

test "without non included components" {
    const ComponentA = struct { a: f32 };
    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = eczinho.BundleContext.Builder.init()
        .build(Entity);
    try std.testing.expect(std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA) == null);
}

test "with given components" {
    const ComponentA = struct { a: f32 };
    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = eczinho.BundleContext.Builder.init()
        .addComponent(ComponentA)
        .build(Entity);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA) != null);
}

test "include multiple components at once" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };

    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = eczinho.BundleContext.Builder.init()
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
    const Context = eczinho.BundleContext.Builder.init()
        .addComponent(ComponentA)
        .addComponent(ComponentB)
        .addComponent(ComponentC)
        .build(Entity);

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentC) != null);
}

test "include components individually and at once" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };

    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = eczinho.BundleContext.Builder.init()
        .addComponents(&.{ ComponentA, ComponentB })
        .addComponent(ComponentC)
        .build(Entity);

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ComponentTypes, ComponentC) != null);
}

