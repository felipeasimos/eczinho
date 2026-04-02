const eczinho = @import("eczinho");
const std = @import("std");

test "duplicated subbundle in different bundles" {
    const typeA = struct { a: f32 };
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addResource(typeA)
                    .addEvent(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addBundle(bundleA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleC: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addBundle(bundleA)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundleB)
        .addBundle(bundleC)
        .build();
    try std.testing.expect(Context.Components.isComponent(typeA));
    try std.testing.expect(Context.Resources.isResource(typeA));
    try std.testing.expect(Context.Events.isEvent(typeA));
    try std.testing.expectEqual(1, Context.Components.Len);
    try std.testing.expectEqual(1 + eczinho.AppEvents.appEventsSlice.len, Context.Events.Len);
    try std.testing.expectEqual(1, Context.Resources.Len);

    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleA));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleB));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleC));
    try std.testing.expectEqual(3, Context.Bundles.len);
}

test "duplicate primary and subsubbundle" {
    const typeA = struct { a: f32 };
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addResource(typeA)
                    .addEvent(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addBundle(bundleA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleC: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addBundle(bundleB)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundleC)
        .addBundle(bundleA)
        .build();
    try std.testing.expect(Context.Components.isComponent(typeA));
    try std.testing.expect(Context.Resources.isResource(typeA));
    try std.testing.expect(Context.Events.isEvent(typeA));
    try std.testing.expectEqual(1, Context.Components.Len);
    try std.testing.expectEqual(1 + eczinho.AppEvents.appEventsSlice.len, Context.Events.Len);
    try std.testing.expectEqual(1, Context.Resources.Len);

    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleA));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleB));
    try std.testing.expect(eczinho.Bundle.containsBundle(Context.Bundles, bundleC));
    try std.testing.expectEqual(3, Context.Bundles.len);
}
