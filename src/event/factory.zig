const EventStoreFactory = @import("event_store.zig").EventStore;
const SystemData = @import("../system_data.zig").SystemData;
const ParameterData = @import("../parameter_data.zig").ParameterData;

pub const EventOptions = struct {
    Events: type,
    T: type,
};

pub fn EventWriter(comptime options: EventOptions) type {
    return struct {
        pub const Marker = EventWriter;
        pub const T = options.T;
        pub const Events = options.Events;
        pub const EventStore = EventStoreFactory(.{
            .Events = Events,
        });

        store: *EventStore,
        pub fn init(store: *EventStore) @This() {
            return .{
                .store = store,
            };
        }
        pub fn deinit(self: *@This()) void {
            _ = self;
        }
        pub fn write(self: @This(), value: T) void {
            self.store.write(value) catch @panic("panic when trying to write to event store");
        }
    };
}

pub fn EventReader(comptime options: EventOptions) type {
    return struct {
        pub const Marker = EventReader;
        pub const T = options.T;
        pub const Events = options.Events;
        pub const EventStore = EventStoreFactory(.{
            .Events = Events,
        });
        pub const Reader = @This();

        store: *EventStore,
        data: *SystemData,
        param: ParameterData,
        pub fn init(store: *EventStore, data: *SystemData, param: ParameterData) @This() {
            return .{
                .store = store,
                .data = data,
                .param = param,
            };
        }
        pub fn deinit(self: *@This()) void {
            _ = self;
        }
        fn getReaderIndexPtr(self: @This()) *usize {
            return self.data.getEventReaderIndexPtr(self.param.type_index);
        }
        pub fn readOne(self: @This()) ?T {
            return self.store.readOne(T, self.getReaderIndexPtr());
        }
        /// how many events are left to read
        pub fn remaining(self: @This()) usize {
            return self.store.remaining(T, self.getReaderIndexPtr());
        }
        pub fn empty(self: @This()) bool {
            return self.remaining() == 0;
        }
        pub fn clear(self: @This()) void {
            return self.store.clear(T, self.getReaderIndexPtr());
        }
        pub fn iterator(self: @This()) Iterator {
            return Iterator.init(self);
        }
        pub const Iterator = struct {
            reader: *Reader,
            pub fn init(reader: *Reader) @This() {
                return .{
                    .reader = reader,
                };
            }
            pub fn next(self: *@This()) ?T {
                return self.reader.readOne();
            }
        };
    };
}

test EventWriter {
    const std = @import("std");
    const Events = @import("events.zig").Events(&.{ u64, u32 });
    const EventStore = EventStoreFactory(.{
        .Events = Events,
    });
    var store = EventStore.init(std.testing.allocator);
    defer store.deinit();

    var writer = EventWriter(.{ .Events = Events, .T = u64 }).init(&store);
    defer writer.deinit();
    writer.write(@as(u64, 8));
}

test EventReader {
    const std = @import("std");
    const Events = @import("events.zig").Events(&.{ u64, u32 });
    const EventStore = EventStoreFactory(.{
        .Events = Events,
    });
    var store = EventStore.init(std.testing.allocator);
    defer store.deinit();

    var data = try SystemData.init(std.testing.allocator, 1, 1);
    defer data.deinit(std.testing.allocator);

    const param = ParameterData{ .global_index = 0, .type_index = 0 };

    var reader = EventReader(.{ .Events = Events, .T = u64 }).init(&store, &data, param);
    defer reader.deinit();

    try std.testing.expectEqual(0, reader.remaining());
    try std.testing.expectEqual(true, reader.empty());
    try std.testing.expectEqual(null, reader.readOne());
    reader.clear();
}
