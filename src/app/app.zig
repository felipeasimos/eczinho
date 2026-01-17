const std = @import("std");
const System = @import("../system.zig").System;
const SchedulerLabel = @import("../scheduler.zig").SchedulerLabel;
const ComponentsFactory = @import("../components.zig").Components;
const RegistryFactory = @import("../registry.zig").Registry;

pub const AppOptions = struct {
    Components: []const type = &.{},
    Systems: []System = &.{},
    SchedulerLabels: []SchedulerLabel = &.{},
    Entity: type = .medium,
};

/// comptime struct used to encapsulate part of an application in modularized
/// and reusable way
/// includes:
/// - Components
/// - Systems
pub fn App(comptime options: AppOptions) type {
    return struct {
        pub const ComponentTypes = options.Components;
        pub const Entity = options.Entity;
        pub const ComponentBitSet = ComponentsFactory(ComponentTypes);
        pub const Registry = RegistryFactory(.{
            .ComponentTypes = ComponentTypes,
            .Entity = Entity,
        });

        allocator: std.mem.Allocator,
        registry,
    };
}
