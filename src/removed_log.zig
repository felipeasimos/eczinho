const std = @import("std");
const Tick = @import("types.zig").Tick;

pub fn RemovedLog(comptime Entity: type) type {
    return struct {
        const RemovedEntry = struct {
            entity: Entity,
            tick: Tick,
        };
        arr: std.ArrayList(Tick) = .empty,
        min: Tick,

        pub fn init() @This() {
            return .{
                .arr = .empty,
            };
        }
        pub fn append(self: *@This(), alloc: std.mem.Allocator, entt: Entity, tick: Tick) !void {
            try self.arr.append(alloc, .{
                .entity = entt,
                .tick = tick,
            });
        }
    };
}
