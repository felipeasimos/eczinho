const std = @import("std");
const TypeStoreFactory = @import("../resource/type_store.zig").TypeStore;
const EventStoreFactory = @import("../event/event_store.zig").EventStore;
const RemovedLogFactory = @import("../removed/removed_log.zig").RemovedComponentsLog;
const SystemData = @import("../system/system_data.zig").SystemData;
const StageLabel = @import("stage_label.zig").StageLabel;
const Constraint = @import("../constraint/constraint.zig").Constraint;
const dag = @import("dag.zig");
const system = @import("../system/system.zig");

pub const SchedulerOptions = struct {
    Context: type,
    Systems: []const type,
    Labels: []const StageLabel,
    Constraints: []const Constraint,
};

fn initSchedulerStages(
    comptime systems: []const type,
    comptime labels: []const StageLabel,
) std.EnumArray(StageLabel, []const type) {
    var stages = std.EnumArray(StageLabel, []const type).initFill(&.{});
    for (std.enums.values(StageLabel)) |label| {
        var stage_systems: []const type = &.{};
        for (systems, 0..) |sys, i| {
            if (labels[i] == label) {
                stage_systems = stage_systems ++ .{sys};
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
        pub const DAG = dag.DAG;
        pub const Labels = options.Labels;
        pub const SchedulerStages = initSchedulerStages(Systems, Labels);
        pub const World = options.Context.GetWorldType();
        pub const TypeStore = TypeStoreFactory(.{
            .TypeHasher = Resources,
        });
        pub const EventStore = EventStoreFactory(.{
            .Events = Events,
        });
        pub const RemovedLog = RemovedLogFactory(.{
            .Components = Components,
            .Entity = Entity,
        });
        pub const Constraints: []const Constraint = options.Constraints;
        const Sched = @This();

        world: *World,
        resource_store: *TypeStore,
        event_store: *EventStore,
        system_data: [Systems.len]SystemData,
        io: std.Io,

        pub fn init(reg: *World, resource_store: *TypeStore, event_store: *EventStore, io: std.Io) !@This() {
            var new: @This() = .{
                .resource_store = resource_store,
                .world = reg,
                .event_store = event_store,
                // SAFETY: immediatly populated in the following lines
                .system_data = undefined,
                .io = io,
            };
            inline for (Systems, 0..) |System, i| {
                new.system_data[i] = try System.initData(reg.allocator);
            }
            try new.runStage(.Startup);
            try new.syncBarrier();
            return new;
        }

        pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
            for (self.system_data) |data| {
                data.deinit(allocator);
            }
        }

        fn getSystemIndex(comptime System: type) usize {
            inline for (Systems, 0..) |_, i| {
                if (comptime system.isSameSystem(Systems[i], System)) {
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
            try self.world.sync();
        }
        fn Runnable(comptime S: type) type {
            return struct {
                pub fn run(scheduler: *Sched) std.Io.Cancelable!void {
                    const system_data_ptr = scheduler.getSystemData(S);
                    S.call(.{
                        .world = scheduler.world,
                        .type_store = scheduler.resource_store,
                        .event_store = scheduler.event_store,
                        .removed_logs = &scheduler.world.removed,
                        .io = scheduler.io,
                        .allocator = scheduler.world.allocator,
                        .system_data = system_data_ptr,
                    }) catch {
                        return error.Canceled;
                    };
                    system_data_ptr.last_run = scheduler.world.getTick();
                }
            };
        }
        fn runSystemsInParallel(self: *@This(), comptime systems: []const type) !void {
            var group = std.Io.Group.init;
            inline for (systems) |sys| {
                try group.concurrent(self.io, Runnable(sys).run, .{self});
            }
            try group.await(self.io);
        }
        fn runSystem(self: *@This(), comptime sys: type) !void {
            return Runnable(sys).run(self);
        }
        fn runStageDAG(self: *@This(), comptime label: StageLabel, comptime num_threads: usize) !void {
            const systems = comptime SchedulerStages.get(label);
            const LabelDAG = dag.DAG(systems, Components, Resources, Events, num_threads, Constraints);
            inline for (LabelDAG.ParallelGroups) |ParallelGroup| {
                try self.runSystemsInParallel(ParallelGroup.Systems);
            }
        }
        fn runStage(self: *@This(), comptime label: StageLabel) !void {
            inline for (comptime SchedulerStages.get(label)) |sys| {
                try self.runSystem(sys);
            }
        }

        pub fn run(self: *@This()) !void {
            try self.syncBarrier();
            inline for (comptime std.enums.values(StageLabel)[1..]) |label| {
                const num_threads = comptime Constraint.getStageNumThreads(Constraints, label);
                if (comptime num_threads == 1) {
                    // using the main thread instead of worker threads is important for final rendering using opengl/raylib
                    try self.runStage(label);
                } else {
                    try self.runStageDAG(label, num_threads);
                }
            }
        }
    };
}
