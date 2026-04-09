const std = @import("std");
const EventBuffer = @import("buffer.zig").EventBuffer;

pub const EventStoreOptions = struct {
    Events: type,
};

fn CreateBuffersTupleType(comptime Events: type) type {
    var field_types: [Events.Len]type = undefined;
    var iter = comptime Events.Iterator.init();
    var i = 0;
    inline while (iter.nextType()) |Type| {
        const BufferType = EventBuffer(Type);
        field_types[i] = BufferType;
        i += 1;
    }
    return @Tuple(&field_types);
}

pub fn EventStore(comptime options: EventStoreOptions) type {
    return struct {
        pub const Marker = EventStore;
        pub const Events = options.Events;
        pub const EventReaderData = struct {
            next_index_to_read: usize = 0,
        };
        pub const BuffersTuple = CreateBuffersTupleType(Events);

        allocator: std.mem.Allocator,
        buffers: BuffersTuple,

        pub fn init(allocator: std.mem.Allocator) @This() {
            comptime var iter = Events.Iterator.init();
            comptime var i = 0;
            // SAFETY: immediatly filled in the following lines
            var buffers: BuffersTuple = undefined;
            inline while (iter.nextType()) |Type| {
                buffers[i] = EventBuffer(Type).init();
                i += 1;
            }
            return .{
                .allocator = allocator,
                .buffers = buffers,
            };
        }
        pub fn deinit(self: *@This()) void {
            comptime var iter = Events.Iterator.init();
            comptime var i = 0;
            inline while (iter.nextType()) |_| {
                self.buffers[i].deinit(self.allocator);
                i += 1;
            }
        }
        pub fn swap(self: *@This()) void {
            comptime var iter = Events.Iterator.init();
            inline while (iter.nextType()) |Type| {
                self.buffers[Events.getIndex(Type)].swap(self.allocator);
            }
        }
        fn getBuffer(self: *@This(), comptime T: type) *EventBuffer(T) {
            return &self.buffers[Events.getIndex(T)];
        }
        pub fn write(self: *@This(), value: anytype) !void {
            return self.getBuffer(@TypeOf(value)).write(self.allocator, value);
        }
        pub fn readOne(self: *@This(), comptime T: type, index_ptr: *usize) ?T {
            return self.getBuffer(T).readOne(index_ptr);
        }
        pub fn remaining(self: *@This(), comptime T: type, index_ptr: *usize) usize {
            return self.getBuffer(T).remaining(index_ptr);
        }
        pub fn clear(self: *@This(), comptime T: type, index_ptr: *usize) void {
            self.getBuffer(T).clear(index_ptr);
        }
        pub fn total(self: *@This(), comptime T: type) usize {
            return self.getBuffer(T).count;
        }
    };
}

test EventStore {
    const Events = @import("events.zig").Events;
    const EventStoreType = EventStore(.{ .Events = Events(&.{ u64, u32 }) });
    var store = EventStoreType.init(std.testing.allocator);
    defer store.deinit();

    try store.write(@as(u64, 1));
    try store.write(@as(u64, 2));
    try store.write(@as(u64, 3));

    try store.write(@as(u32, 4));
    try store.write(@as(u32, 5));
    try store.write(@as(u32, 6));

    var u64_cursor: usize = 0;
    var u32_cursor: usize = 0;

    try std.testing.expectEqual(0, store.remaining(u64, &u64_cursor));
    try std.testing.expectEqual(0, store.remaining(u32, &u32_cursor));
    store.swap();
    try std.testing.expectEqual(3, store.remaining(u64, &u64_cursor));
    try std.testing.expectEqual(3, store.remaining(u32, &u32_cursor));

    // u64
    try std.testing.expectEqual(1, store.readOne(u64, &u64_cursor));
    try std.testing.expectEqual(2, store.remaining(u64, &u64_cursor));

    store.clear(u64, &u64_cursor);

    try std.testing.expectEqual(0, store.remaining(u64, &u64_cursor));

    // u32
    try std.testing.expectEqual(4, store.readOne(u32, &u32_cursor));
    try std.testing.expectEqual(2, store.remaining(u32, &u32_cursor));

    store.clear(u32, &u32_cursor);

    try std.testing.expectEqual(0, store.remaining(u32, &u32_cursor));
}
