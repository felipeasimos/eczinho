const std = @import("std");
const EventBuffer = @import("buffer.zig").EventBuffer;

pub const EventStoreOptions = struct {
    Events: type,
};

fn initBuffersTuple(comptime Events: type) type {
    var fields: [Events.Len]std.builtin.Type.StructField = undefined;
    var iter = comptime Events.Iterator.init();
    var i = 0;
    inline while (iter.nextType()) |Type| {
        const BufferType = EventBuffer(Type);
        fields[i] = std.builtin.Type.StructField{
            .name = std.fmt.comptimePrint("{}", .{i}),
            .type = BufferType,
            .alignment = @alignOf(BufferType),
            .is_comptime = false,
            .default_value_ptr = null,
        };
        i += 1;
    }
    return @Type(.{
        .@"struct" = .{
            .backing_integer = null,
            .layout = .auto,
            .decls = &.{},
            .is_tuple = true,
            .fields = &fields,
        },
    });
}

pub fn EventStore(comptime options: EventStoreOptions) type {
    return struct {
        pub const Events = options.Events;
        pub const EventReaderData = struct {
            next_index_to_read: usize = 0,
        };
        pub const BuffersTuple = initBuffersTuple(Events);

        buffers: BuffersTuple,
        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) @This() {
            var buffers: BuffersTuple = undefined;
            comptime var iter = Events.Iterator.init();
            comptime var i = 0;
            inline while (iter.nextType()) |Type| {
                buffers[i] = EventBuffer(Type).init(alloc);
                i += 1;
            }
            return .{
                .allocator = alloc,
                .buffers = buffers,
            };
        }
        pub fn deinit(self: *@This()) void {
            comptime var iter = Events.Iterator.init();
            comptime var i = 0;
            inline while (iter.nextType()) |_| {
                self.buffers[i].deinit();
                i += 1;
            }
        }
        pub fn swap(self: *@This()) void {
            comptime var iter = Events.Iterator.init();
            comptime var i = 0;
            inline while (iter.nextType()) |_| {
                self.buffers[i].swap();
                i += 1;
            }
        }
        pub fn reserveEventReaderData(self: *@This(), n: usize) !void {
            try self.event_reader_indices.appendNTimes(self.allocator, .{}, n);
        }
        fn getBuffer(self: *@This(), comptime T: type) *EventBuffer(T) {
            return &self.buffers[Events.getIndex(T)];
        }
        pub fn write(self: *@This(), value: anytype) !void {
            const buffer = self.getBuffer(@TypeOf(value));
            try buffer.write(value);
        }
        pub fn read(self: *@This(), comptime T: type, index: usize) T {
            return self.getBuffer(T).read(index);
        }
        pub fn len(self: *@This(), comptime T: type, index: usize) usize {
            return self.getBuffer(T).len() - index;
        }
    };
}
