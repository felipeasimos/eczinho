const eczinho = @import("eczinho");
const std = @import("std");

test "without non included resources" {
    const ResourceA = struct { a: f32 };
    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = eczinho.BundleContext.Builder.init()
        .build(Entity);
    try std.testing.expect(std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceA) == null);
}

test "with given resources" {
    const ResourceA = struct { a: f32 };
    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = eczinho.BundleContext.Builder.init()
        .addResource(ResourceA)
        .build(Entity);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceA) != null);
}

test "include multiple resources at once" {
    const ResourceA = struct { a: f32 };
    const ResourceB = struct { a: u31 };
    const ResourceC = struct { a: u30 };

    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = eczinho.BundleContext.Builder.init()
        .addResources(&.{ ResourceA, ResourceB, ResourceC })
        .build(Entity);

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceC) != null);
}

test "include multiple resources individually" {
    const ResourceA = struct { a: f32 };
    const ResourceB = struct { a: u31 };
    const ResourceC = struct { a: u30 };

    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = eczinho.BundleContext.Builder.init()
        .addResource(ResourceA)
        .addResource(ResourceB)
        .addResource(ResourceC)
        .build(Entity);

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceC) != null);
}

test "include resources individually and at once" {
    const ResourceA = struct { a: f32 };
    const ResourceB = struct { a: u31 };
    const ResourceC = struct { a: u30 };

    const Entity = eczinho.entity.EntityTypeFactory(.medium);
    const Context = eczinho.BundleContext.Builder.init()
        .addResources(&.{ ResourceA, ResourceB })
        .addResource(ResourceC)
        .build(Entity);

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.ResourceTypes, ResourceC) != null);
}
