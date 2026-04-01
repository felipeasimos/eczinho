const eczinho = @import("eczinho");
const std = @import("std");

test "duplicated component/event/resource in different bundles with config override" {
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
        .overrideComponentConfig(typeA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
        .build();
    try std.testing.expect(Context.Components.isComponent(typeA));
    try std.testing.expect(Context.Resources.isResource(typeA));
    try std.testing.expect(Context.Events.isEvent(typeA));
    try std.testing.expectEqual(1, Context.Components.Len);
    try std.testing.expectEqual(1 + eczinho.AppEvents.appEventsSlice.len, Context.Events.Len);
    try std.testing.expectEqual(1, Context.Resources.Len);

    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.Components.getConfig(typeA));
}

test "duplicated subbundle in different bundles with config override" {
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
        .overrideComponentConfig(typeA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
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

    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.Components.getConfig(typeA));
}

test "duplicate primary and subsubbundle with config override" {
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
        .overrideComponentConfig(typeA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
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

    try std.testing.expectEqual(eczinho.ComponentConfig{
        .storage_type = .Sparse,
        .track_metadata = .{
            .added = false,
            .changed = false,
        },
    }, Context.Components.getConfig(typeA));
}
