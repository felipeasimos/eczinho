const eczinho = @import("eczinho");
const std = @import("std");

test "without non included events" {
    const EventA = struct { a: f32 };
    const Context = comptime eczinho.BundleContext.Builder.init()
        .build();
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventA) == null);
}

test "with given events" {
    const EventA = struct { a: f32 };
    const Context = comptime eczinho.BundleContext.Builder.init()
        .addEvent(EventA)
        .build();
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventA) != null);
}

test "include multiple events at once" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u31 };
    const EventC = struct { a: u30 };

    const Context = comptime eczinho.BundleContext.Builder.init()
        .addEvents(&.{ EventA, EventB, EventC })
        .build();

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventC) != null);
}

test "include multiple events individually" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u31 };
    const EventC = struct { a: u30 };

    const Context = comptime eczinho.BundleContext.Builder.init()
        .addEvent(EventA)
        .addEvent(EventB)
        .addEvent(EventC)
        .build();

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventC) != null);
}

test "include events individually and at once" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u31 };
    const EventC = struct { a: u30 };

    const Context = comptime eczinho.BundleContext.Builder.init()
        .addEvents(&.{ EventA, EventB })
        .addEvent(EventC)
        .build();

    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventA) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventB) != null);
    try std.testing.expect(comptime std.mem.indexOfScalar(type, Context.EventTypes, EventC) != null);
}
