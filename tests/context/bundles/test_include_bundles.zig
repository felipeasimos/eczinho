const eczinho = @import("eczinho");
const std = @import("std");

test "without non included bundles" {
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .build();
    try std.testing.expect(!eczinho.Bundle.containsBundle(Context.Bundles, bundleA));
}

test "with given bundles" {
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundleA)
        .build();
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleA));
}

test "include multiple bundles at once" {
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const bundleC: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundles(&.{ bundleA, bundleB, bundleC })
        .build();
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleA));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleB));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleC));
}

test "include multiple bundles individually" {
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const bundleC: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundleA)
        .addBundle(bundleB)
        .addBundle(bundleC)
        .build();
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleA));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleB));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleC));
}

test "include bundles individually and at once" {
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const bundleC: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime _: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build();
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundles(&.{ bundleA, bundleB })
        .addBundle(bundleC)
        .build();
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleA));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleB));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleC));
}
