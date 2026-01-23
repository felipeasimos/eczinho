const std = @import("std");
const System = @import("system.zig").System;
const RegistryFactory = @import("registry.zig").Registry;

pub const SchedulerLabel = enum {
    Startup,
    Update,
    Render,
};

pub const SchedulerOptions = struct {
    Context: type,
    Systems: []const System,
};

fn initSchedulerStages(comptime systems: []const System) std.EnumArray(SchedulerLabel, []const System) {
    var stages = std.EnumArray(SchedulerLabel, []const System).initFill(&.{});
    for (std.enums.values(SchedulerLabel)) |label| {
        var stage_systems: []const System = &.{};
        for (systems) |system| {
            if (system.scheduler_label == label) {
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
        pub const Systems = options.Systems;
        pub const SchedulerStages = initSchedulerStages(Systems);
        pub const Registry = RegistryFactory(.{
            .Components = Components,
            .Entity = Entity,
        });

        registry: *Registry,

        pub fn init(reg: *Registry) !@This() {
            var new: @This() = .{
                .registry = reg,
            };
            try new.runStage(.Startup);
            return new;
        }

        fn runStage(self: *@This(), comptime label: SchedulerLabel) !void {
            inline for (SchedulerStages.get(label)) |system| {
                // SAFETY: immediatly filled in the following lines
                var args: system.args_tuple_type = undefined;
                inline for (system.param_types, 0..) |t, i| {
                    args[i] = try t.init(self.registry);
                }
                try system.call(args);
                inline for (system.param_types, 0..) |_, i| {
                    args[i].deinit();
                }
            }
            try self.registry.sync();
        }

        pub fn next(self: *@This()) void {
            // run every stage in order, except for startup
            inline for (comptime std.enums.values(SchedulerLabel)[1..]) |label| {
                self.runStage(label);
            }
        }
    };
}
