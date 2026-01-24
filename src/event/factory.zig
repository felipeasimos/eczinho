const EventStoreFactory = @import("event_store.zig").EventStore;

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
        pub const Marker = EventWriter;
        pub const T = options.T;
        pub const Events = options.Events;
        pub const EventStore = EventStoreFactory(.{
            .Events = Events,
        });
        pub const Reader = @This();

        store: *EventStore,
        index: usize,
        pub fn init(store: *EventStore, index: usize) @This() {
            return .{
                .store = store,
                .index = index,
            };
        }
        pub fn deinit(self: *@This()) void {
            _ = self;
        }
        pub fn read(self: *@This()) T {
            const value = self.store.read(T, self.index);
            self.index += 1;
            return value;
        }
        /// how many events are left to read
        pub fn len(self: *@This()) usize {
            return self.store.len(T, self.index);
        }
        pub fn empty(self: *@This()) bool {
            return self.len() == 0;
        }
        pub fn iterator(self: *@This()) Iterator {
            return Iterator.init(self);
        }
        pub const Iterator = struct {
            reader: *Reader,
            pub fn init(reader: *Reader) @This() {
                return .{
                    .reader = reader,
                };
            }
            pub fn next(self: *@This()) T {
                return self.reader.read();
            }
        };
    };
}
