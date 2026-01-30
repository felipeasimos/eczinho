const std = @import("std");
const Tick = @import("../types.zig").Tick;
const Messages = @import("../messages.zig").Messages;

pub const RemovedComponentsLogOptions = struct {
    Entity: type,
    Components: type,
};

pub fn RemovedComponentsLog(comptime options: RemovedComponentsLogOptions) type {
    return struct {
        pub const Components = options.Components;
        pub const Entity = options.Entity;

        const RemovedLogEntryType = struct {
            entity: Entity,
            tick: Tick,
        };
        const RemovedComponentLogType = Messages(RemovedLogEntryType);
        logs: [Components.Len]RemovedComponentLogType,

        pub fn init(alloc: std.mem.Allocator) @This() {
            var new: @This() = undefined;
            for (0..Components.Len) |i| {
                new.logs[i] = RemovedComponentLogType.init(alloc);
            }
            return new;
        }
        pub fn deinit(self: *@This()) void {
            for (0..Components.Len) |i| {
                self.logs[i].deinit();
            }
        }
        pub fn swap(self: *@This()) void {
            for (0..Components.Len) |i| {
                self.logs[i].swap();
            }
        }
        pub fn getRemovedLog(self: *@This(), tid_or_component: anytype) *RemovedComponentLogType {
            return &self.logs[Components.getIndex(tid_or_component)];
        }
        pub fn readOne(self: *@This(), comptime T: type, index_ptr: *usize) ?RemovedLogEntryType {
            return self.getRemovedLog(T).readOne(index_ptr);
        }
        pub fn remaining(self: *@This(), comptime T: type, index_ptr: *usize) usize {
            return self.getRemovedLog(T).remaining(index_ptr);
        }
        pub fn clear(self: *@This(), comptime T: type, index_ptr: *usize) void {
            self.getRemovedLog(T).clear(index_ptr);
        }
        pub fn total(self: *@This(), comptime T: type) usize {
            return self.getRemovedLog(T).count;
        }
        pub fn addRemoved(self: *@This(), tid_or_component: anytype, entt: Entity, current_tick: Tick) !void {
            try self.getRemovedLog(tid_or_component).write(.{
                .entity = entt,
                .tick = current_tick,
            });
        }
    };
}
