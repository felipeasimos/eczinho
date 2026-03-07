const eczinho = @import("eczinho");
const std = @import("std");

fn hasAppEvents(Context: type) bool {
    if (!Context.Events.isEvent(eczinho.AppEvents.AppExit)) return false;
    return true;
}

test "without non included events" {
    const EventA = struct { a: f32 };
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
    try std.testing.expect(!Context.Events.isEvent(EventA));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
    try std.testing.expect(hasAppEvents(Context));
}

test "with given events" {
    const EventA = struct { a: f32 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addEvent(EventA)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Events.isEvent(EventA));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
    try std.testing.expect(hasAppEvents(Context));
}

test "include multiple events at once" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u31 };
    const EventC = struct { a: u30 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addEvents(&.{ EventA, EventB, EventC })
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Events.isEvent(EventA));
    try std.testing.expect(Context.Events.isEvent(EventB));
    try std.testing.expect(Context.Events.isEvent(EventC));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
    try std.testing.expect(hasAppEvents(Context));
}

test "include multiple events individually" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u31 };
    const EventC = struct { a: u30 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addEvent(EventA)
                    .addEvent(EventB)
                    .addEvent(EventC)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Events.isEvent(EventA));
    try std.testing.expect(Context.Events.isEvent(EventB));
    try std.testing.expect(Context.Events.isEvent(EventC));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
    try std.testing.expect(hasAppEvents(Context));
}

test "include events individually and at once" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u31 };
    const EventC = struct { a: u30 };
    const bundle: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .addEvents(&.{ EventA, EventB })
                    .addEvent(EventC)
                    .build(Entity);
            }
        }).constructor,
    };
    const Context = eczinho.AppContextBuilder.init()
        .addBundle(bundle)
        .build();
    try std.testing.expect(Context.Events.isEvent(EventA));
    try std.testing.expect(Context.Events.isEvent(EventB));
    try std.testing.expect(Context.Events.isEvent(EventC));
    try std.testing.expectEqual(&.{bundle}, Context.Bundles);
    try std.testing.expect(hasAppEvents(Context));
}
