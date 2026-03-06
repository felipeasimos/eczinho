const RemovedLogFactory = @import("removed_log.zig").RemovedComponentsLog;
const SystemData = @import("../system_data.zig").SystemData;
const ParameterData = @import("../parameter_data.zig").ParameterData;

pub const RemovedOptions = struct {
    Components: type,
    Entity: type,
    T: type,
    Tick: type,
};

pub fn Removed(comptime options: RemovedOptions) type {
    return struct {
        pub const Marker = Removed;
        pub const T = options.T;
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const Tick = options.Tick;
        pub const RemovedLog = RemovedLogFactory(.{
            .Entity = Entity,
            .Components = Components,
        });

        pub const Reader = @This();

        logs: *RemovedLog,
        data: *SystemData,
        param: ParameterData,
        pub fn init(logs: *RemovedLog, data: *SystemData, param: ParameterData) @This() {
            return .{
                .logs = logs,
                .data = data,
                .param = param,
            };
        }
        pub fn deinit(self: *@This()) void {
            _ = self;
        }
        fn getReaderIndexPtr(self: @This()) *usize {
            return self.data.getRemovedReaderIndexPtr(self.param.type_index);
        }
        pub fn readOne(self: @This()) ?Entity {
            if (self.logs.readOne(T, self.getReaderIndexPtr())) |entry| {
                return entry.entity;
            }
            return null;
        }
        /// how many events are left to read
        pub fn remaining(self: @This()) usize {
            return self.logs.remaining(T, self.getReaderIndexPtr());
        }
        pub fn empty(self: @This()) bool {
            return self.remaining() == 0;
        }
        pub fn clear(self: @This()) void {
            return self.logs.clear(T, self.getReaderIndexPtr());
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
            pub fn next(self: *@This()) ?Entity {
                return self.reader.readOne();
            }
        };
    };
}
