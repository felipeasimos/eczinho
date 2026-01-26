const std = @import("std");
const RegistryFactory = @import("registry.zig").Registry;
const TypeStoreFactory = @import("resource/type_store.zig").TypeStore;
const EventStoreFactory = @import("event/event_store.zig").EventStore;
const SystemData = @import("system_data.zig").SystemData;

pub const SchedulerLabel = enum {
    Startup,
    Update,
    Render,
};

pub const SchedulerOptions = struct {
    Context: type,
    Systems: []const type,
    Labels: []const SchedulerLabel,
};

fn initSchedulerStages(comptime systems: []const type, comptime labels: []const SchedulerLabel) std.EnumArray(SchedulerLabel, []const type) {
    var stages = std.EnumArray(SchedulerLabel, []const type).initFill(&.{});
    for (std.enums.values(SchedulerLabel)) |label| {
        var stage_systems: []const type = &.{};
        for (systems, 0..) |system, i| {
            if (labels[i] == label) {
                stage_systems = stage_systems ++ .{system};
            }
        }
        stages.set(label, stage_systems);
    }
    return stages;
}

pub fn Scheduler(comptime options: SchedulerOptions) type {
    return struct {
        pub const Components = options.Context.Components;
        pub const Entity = options.Context.Entity;
        pub const Resources = options.Context.Resources;
        pub const Events = options.Context.Events;
        pub const Systems = options.Systems;
        pub const Labels = options.Labels;
        pub const SchedulerStages = initSchedulerStages(Systems, Labels);
        pub const Registry = RegistryFactory(.{
            .Components = Components,
            .Entity = Entity,
        });
        pub const TypeStore = TypeStoreFactory(.{
            .Resources = Resources,
        });
        pub const EventStore = EventStoreFactory(.{
            .Events = Events,
        });

        registry: *Registry,
        resource_store: *TypeStore,
        event_store: *EventStore,
        system_data: [Systems.len]SystemData,

        pub fn init(reg: *Registry, resource_store: *TypeStore, event_store: *EventStore) !@This() {
            var new: @This() = .{
                .resource_store = resource_store,
                .registry = reg,
                .event_store = event_store,
                // SAFETY: immediatly populated in the following lines
                .system_data = undefined,
            };
            inline for (Systems, 0..) |System, i| {
                new.system_data[i] = try System.initData(reg.allocator);
            }
            try new.runStage(.Startup);
            return new;
        }

        pub fn deinit(self: *const @This()) void {
            for (self.system_data) |data| {
                data.deinit(self.registry.allocator);
            }
        }

        fn getSystemIndex(comptime System: type) usize {
            inline for (Systems, 0..) |_, i| {
                if (Systems[i] == System) {
                    return i;
                }
            }

            @compileError(std.fmt.comptimePrint("System {} is not registered", .{System}));
        }

        fn runStage(self: *@This(), comptime label: SchedulerLabel) !void {
            inline for (SchedulerStages.get(label)) |system| {
                const system_data_ptr = &self.system_data[getSystemIndex(system)];
                try system.call(.{
                    .registry = self.registry,
                    .type_store = self.resource_store,
                    .event_store = self.event_store,
                    .system_data = system_data_ptr,
                });
            }
            // sync deferred changes
            try self.registry.sync();
            // swap event buffers
            self.event_store.swap();
        }

        pub fn next(self: *@This()) void {
            // run every stage in order, except for startup
            inline for (comptime std.enums.values(SchedulerLabel)[1..]) |label| {
                self.runStage(label);
            }
        }
    };
}
