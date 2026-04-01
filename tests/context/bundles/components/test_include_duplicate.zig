const eczinho = @import("eczinho");
const std = @import("std");

test "duplicated component/event/resource in different bundles" {
    const typeA = struct { a: f32 };
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addEvent(typeA)
                    .addResource(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addEvent(typeA)
                    .addResource(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleC: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addEvent(typeA)
                    .addResource(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundleA)
        .addBundle(bundleB)
        .addBundle(bundleC)
        .build();
    try std.testing.expect(Context.Components.isComponent(typeA));
    try std.testing.expect(Context.Resources.isResource(typeA));
    try std.testing.expect(Context.Events.isEvent(typeA));
    try std.testing.expectEqual(1, Context.Components.Len);
    try std.testing.expectEqual(1 + eczinho.AppEvents.appEventsSlice.len, Context.Events.Len);
    try std.testing.expectEqual(1, Context.Resources.Len);
}

test "duplicated component/event/resource in different bundles and specific component configs" {
    const typeA = struct { a: f32 };
    const component_a_config = eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = true,
            .removed = false,
        },
    };
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponentWithConfig(typeA, component_a_config)
                    .addEvent(typeA)
                    .addResource(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponentWithConfig(typeA, .{
                        .storage_type = .Sparse,
                        .track_metadata = .{
                            .added = true,
                            .changed = false,
                            .removed = false,
                        },
                    })
                    .addEvent(typeA)
                    .addResource(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleC: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addEvent(typeA)
                    .addResource(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundleA)
        .addBundle(bundleB)
        .addBundle(bundleC)
        .build();
    try std.testing.expect(Context.Components.isComponent(typeA));
    try std.testing.expect(Context.Resources.isResource(typeA));
    try std.testing.expect(Context.Events.isEvent(typeA));
    try std.testing.expectEqual(1, Context.Components.Len);
    try std.testing.expectEqual(1 + eczinho.AppEvents.appEventsSlice.len, Context.Events.Len);
    try std.testing.expectEqual(1, Context.Resources.Len);
    // first config sets it (unless overwritten)
    try std.testing.expectEqual(component_a_config, Context.Components.getConfig(typeA));
}

test "duplicated subbundle in different bundles" {
    const typeA = struct { a: f32 };
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addEvent(typeA)
                    .addResource(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addEvent(typeA)
                    .addResource(typeA)
                    .addBundle(bundleA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleC: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addEvent(typeA)
                    .addResource(typeA)
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
                    .addEvent(typeA)
                    .addResource(typeA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addEvent(typeA)
                    .addResource(typeA)
                    .addBundle(bundleA)
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleC: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addComponent(typeA)
                    .addEvent(typeA)
                    .addResource(typeA)
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
