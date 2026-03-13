const eczinho = @import("eczinho");
const std = @import("std");

test "without non included events" {
    const EventA = struct { a: f32 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .build();
    try std.testing.expect(!Context.Events.isEvent(EventA));
}

test "with given events" {
    const EventA = struct { a: f32 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addEvent(EventA)
        .build();
    try std.testing.expect(Context.Events.isEvent(EventA));
}

test "include multiple events at once" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u31 };
    const EventC = struct { a: u30 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addEvents(&.{ EventA, EventB, EventC })
        .build();
    try std.testing.expect(Context.Events.isEvent(EventA));
    try std.testing.expect(Context.Events.isEvent(EventB));
    try std.testing.expect(Context.Events.isEvent(EventC));
}

test "include multiple events individually" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u31 };
    const EventC = struct { a: u30 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addEvent(EventA)
        .addEvent(EventB)
        .addEvent(EventC)
        .build();
    try std.testing.expect(Context.Events.isEvent(EventA));
    try std.testing.expect(Context.Events.isEvent(EventB));
    try std.testing.expect(Context.Events.isEvent(EventC));
}

test "include events individually and at once" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u31 };
    const EventC = struct { a: u30 };
    const Context = comptime eczinho.AppContextBuilder.init()
        .addEvents(&.{ EventA, EventB })
        .addEvent(EventC)
        .build();
    try std.testing.expect(Context.Events.isEvent(EventA));
    try std.testing.expect(Context.Events.isEvent(EventB));
    try std.testing.expect(Context.Events.isEvent(EventC));
}
