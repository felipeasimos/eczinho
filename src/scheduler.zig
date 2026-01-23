const std = @import("std");
const System = @import("system.zig").System;
const RegistryFactory = @import("registry.zig").Registry;
const TypeStoreFactory = @import("resource/type_store.zig").TypeStore;

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
        pub const Resources = options.Context.Resources;
        pub const Systems = options.Systems;
        pub const SchedulerStages = initSchedulerStages(Systems);
        pub const Registry = RegistryFactory(.{
            .Components = Components,
            .Entity = Entity,
        });
        pub const TypeStore = TypeStoreFactory(.{
            .Resources = Resources,
        });

        registry: *Registry,
        store: *TypeStore,

        pub fn init(reg: *Registry, store: *TypeStore) !@This() {
            var new: @This() = .{
                .store = store,
                .registry = reg,
            };
            try new.runStage(.Startup);
            return new;
        }

        fn initArg(self: *@This(), comptime ArgType: type) !ArgType {
            const InitArgsTuple = std.meta.ArgsTuple(@TypeOf(ArgType.init));
            var args: InitArgsTuple = undefined;
            const type_info = @typeInfo(@TypeOf(ArgType.init)).@"fn";
            const params = type_info.params;
            inline for (params, 0..) |Param, i| {
                args[i] = switch (comptime Param.type.?) {
                    *TypeStore => self.store,
                    *Registry => self.registry,
                    else => @compileError("Invalid argument for 'init' method in system requirement"),
                };
            }
            const ReturnType = type_info.return_type.?;
            return switch (@typeInfo(ReturnType)) {
                .error_set, .error_union => try @call(.auto, ArgType.init, args),
                else => @call(.auto, ArgType.init, args),
            };
        }

        fn runStage(self: *@This(), comptime label: SchedulerLabel) !void {
            inline for (SchedulerStages.get(label)) |system| {
                // SAFETY: immediatly filled in the following lines
                var args: system.args_tuple_type = undefined;
                inline for (system.param_types, 0..) |T, i| {
                    args[i] = try self.initArg(T);
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
