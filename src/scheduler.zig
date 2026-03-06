const std = @import("std");
const RegistryFactory = @import("registry.zig").Registry;
const TypeStoreFactory = @import("resource/type_store.zig").TypeStore;
const EventStoreFactory = @import("event/event_store.zig").EventStore;
const RemovedLogFactory = @import("removed/removed_log.zig").RemovedComponentsLog;
const SystemData = @import("system_data.zig").SystemData;
const StageLabel = @import("stage_label.zig").StageLabel;

pub const SchedulerOptions = struct {
    Context: type,
    Systems: []const type,
    Labels: []const StageLabel,
};

fn initSchedulerStages(comptime systems: []const type, comptime labels: []const StageLabel) std.EnumArray(StageLabel, []const type) {
    var stages = std.EnumArray(StageLabel, []const type).initFill(&.{});
    for (std.enums.values(StageLabel)) |label| {
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
        pub const RemovedLog = RemovedLogFactory(.{
            .Components = Components,
            .Entity = Entity,
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
            try new.syncBarrier();
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

        fn getSystemData(self: *@This(), comptime System: type) *SystemData {
            return &self.system_data[getSystemIndex(System)];
        }

        fn syncBarrier(self: *@This()) !void {
            // swap event buffers
            self.event_store.swap();
            // sync deferred changes
            try self.registry.sync();
        }
        fn runStage(self: *@This(), comptime label: StageLabel) !void {
            inline for (SchedulerStages.get(label)) |system| {
                const system_data_ptr = self.getSystemData(system);
                try system.call(.{
                    .registry = self.registry,
                    .type_store = self.resource_store,
                    .event_store = self.event_store,
                    .removed_logs = &self.registry.removed,
                    .system_data = system_data_ptr,
                });
                system_data_ptr.last_run = self.registry.getTick();
            }
        }

        pub fn run(self: *@This()) !void {
            try self.syncBarrier();
            // run every stage in order, except for startup
            inline for (comptime std.enums.values(StageLabel)[1..]) |label| {
                try self.runStage(label);
            }
        }
    };
}
