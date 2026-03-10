const eczinho = @import("eczinho");
const std = @import("std");

test "without non included resources" {
    const ResourceA = struct { a: f32 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(!Context.Resources.isResource(ResourceA));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}

test "with given resources" {
    const ResourceA = struct { a: f32 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addResource(ResourceA)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Resources.isResource(ResourceA));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}

test "include multiple resources at once" {
    const ResourceA = struct { a: f32 };
    const ResourceB = struct { a: u31 };
    const ResourceC = struct { a: u30 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addResources(&.{ ResourceA, ResourceB, ResourceC })
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Resources.isResource(ResourceA));
    try std.testing.expect(Context.Resources.isResource(ResourceB));
    try std.testing.expect(Context.Resources.isResource(ResourceC));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}

test "include multiple resources individually" {
    const ResourceA = struct { a: f32 };
    const ResourceB = struct { a: u31 };
    const ResourceC = struct { a: u30 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addResource(ResourceA)
                    .addResource(ResourceB)
                    .addResource(ResourceC)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Resources.isResource(ResourceA));
    try std.testing.expect(Context.Resources.isResource(ResourceB));
    try std.testing.expect(Context.Resources.isResource(ResourceC));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}

test "include resources individually and at once" {
    const ResourceA = struct { a: f32 };
    const ResourceB = struct { a: u31 };
    const ResourceC = struct { a: u30 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addResources(&.{ ResourceA, ResourceB })
                    .addResource(ResourceC)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Resources.isResource(ResourceA));
    try std.testing.expect(Context.Resources.isResource(ResourceB));
    try std.testing.expect(Context.Resources.isResource(ResourceC));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}
