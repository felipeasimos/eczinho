const std = @import("std");
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
        pub fn optRead(self: @This()) ?T {
            const index = self.data.peekNextEventIndex(self.param.type_index);
            if (self.store.optRead(T, index)) |value| {
                _ = self.data.getNextEventIndex(self.param.type_index);
                return value;
            }
            return null;
        }
        pub fn read(self: @This()) T {
            const index = self.data.getNextEventIndex(self.param.type_index);
            return self.store.read(T, index);
        }
        /// how many events are left to read
        pub fn remaining(self: @This()) usize {
            return self.store.remaining(T, self.data.peekNextEventIndex(self.param.type_index));
        }
        pub fn empty(self: @This()) bool {
            return self.remaining() == 0;
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
                return self.reader.read();
            }
        };
    };
}
