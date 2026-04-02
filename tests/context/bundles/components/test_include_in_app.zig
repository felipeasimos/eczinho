const eczinho = @import("eczinho");
const std = @import("std");

test "without non included components" {
    const ComponentA = struct { a: f32 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(!Context.Components.isComponent(ComponentA));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}

test "with given components" {
    const ComponentA = struct { a: f32 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(ComponentA)
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}

test "include multiple components at once" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponents(&.{ ComponentA, ComponentB, ComponentC })
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expect(Context.Components.isComponent(ComponentB));
    try std.testing.expect(Context.Components.isComponent(ComponentC));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}

test "include multiple components individually" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(ComponentA)
                    .addComponent(ComponentB)
                    .addComponent(ComponentC)
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expect(Context.Components.isComponent(ComponentB));
    try std.testing.expect(Context.Components.isComponent(ComponentC));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}

test "include components individually and at once" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponents(&.{ ComponentA, ComponentB })
                    .addComponent(ComponentC)
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expect(Context.Components.isComponent(ComponentB));
    try std.testing.expect(Context.Components.isComponent(ComponentC));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
}
