const eczinho = @import("eczinho");
const std = @import("std");

fn hasAppEvents(Context: type) bool {
    if (!Context.Events.isEvent(eczinho.AppEvents.AppExit)) return false;
    return true;
}

test "empty context has app events" {
    const Context = eczinho.AppContextBuilder.init()
        .build();
    try std.testing.expect(hasAppEvents(Context));
}

test "non empty context has app events" {
    const EventA = struct { a: f32 };
    const Context = eczinho.AppContextBuilder.init()
        .addEvent(EventA)
        .build();
    try std.testing.expect(hasAppEvents(Context));
}

test "non empty context has app events when including multiple events individually" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u32 };
    const EventC = struct { a: u31 };
    const Context = eczinho.AppContextBuilder.init()
        .addEvent(EventA)
        .addEvent(EventB)
        .addEvent(EventC)
        .build();
    try std.testing.expect(hasAppEvents(Context));
}

test "non empty context has app events when including multiple events at once" {
    const EventA = struct { a: f32 };
    const EventB = struct { a: u32 };
    const EventC = struct { a: u31 };
    const Context = eczinho.AppContextBuilder.init()
        .addEvents(&.{ EventA, EventB, EventC })
        .build();
    try std.testing.expect(hasAppEvents(Context));
}
