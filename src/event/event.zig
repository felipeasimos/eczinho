pub const Events = @import("events.zig").Events;
pub const EventStore = @import("event_store.zig").EventStore;
pub const EventReader = @import("factory.zig").EventReader;
pub const EventWriter = @import("factory.zig").EventWriter;

test "event" {
    const std = @import("std");
    const SystemData = @import("../system_data.zig").SystemData;
    const ParameterData = @import("../parameter_data.zig").ParameterData;
    const EmptyType = struct {};
    const TestEvents = @import("events.zig").Events(&.{ u64, EmptyType });
    const TestEventStore = EventStore(.{
        .Events = TestEvents,
    });

    var store = TestEventStore.init(std.testing.allocator);
    defer store.deinit();

    var data = try SystemData.init(std.testing.allocator, 2, 0);
    defer data.deinit(std.testing.allocator);

    const u64_param = ParameterData{ .global_index = 0, .type_index = 0 };
    const empty_param = ParameterData{ .global_index = 1, .type_index = 1 };

    var u64_writer = EventWriter(.{ .Events = TestEvents, .T = u64 }).init(&store);
    defer u64_writer.deinit();
    var empty_writer = EventWriter(.{ .Events = TestEvents, .T = EmptyType }).init(&store);
    defer empty_writer.deinit();

    var u64_reader = EventReader(.{ .Events = TestEvents, .T = u64 }).init(&store, &data, u64_param);
    defer u64_reader.deinit();
    var empty_reader = EventReader(.{ .Events = TestEvents, .T = EmptyType }).init(&store, &data, empty_param);
    defer empty_reader.deinit();

    try std.testing.expectEqual(0, u64_reader.remaining());
    try std.testing.expectEqual(0, empty_reader.remaining());

    u64_writer.write(@as(u64, 1));
    empty_writer.write(.{});

    try std.testing.expectEqual(0, u64_reader.remaining());
    try std.testing.expectEqual(true, u64_reader.empty());
    try std.testing.expectEqual(0, empty_reader.remaining());
    try std.testing.expectEqual(true, empty_reader.empty());

    // clear writes and available reads
    store.swap();
    store.swap();

    // u64
    u64_writer.write(@as(u64, 1));
    u64_writer.write(@as(u64, 2));
    u64_writer.write(@as(u64, 3));

    store.swap();

    u64_writer.write(@as(u64, 4));

    try std.testing.expectEqual(3, u64_reader.remaining());
    try std.testing.expectEqual(1, u64_reader.readOne());
    u64_reader.clear();
    try std.testing.expectEqual(true, u64_reader.empty());

    // empty
    store.swap();
    store.swap();
    try std.testing.expectEqual(0, empty_reader.remaining());
    empty_writer.write(.{});
    empty_writer.write(.{});
    empty_writer.write(.{});
    store.swap();

    try std.testing.expectEqual(3, empty_reader.remaining());
    try std.testing.expectEqual(EmptyType{}, empty_reader.readOne());
    empty_reader.clear();
    try std.testing.expectEqual(true, empty_reader.empty());
}
