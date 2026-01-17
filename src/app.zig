const std = @import("std");
const System = @import("system.zig").System;
const SchedulerLabel = @import("scheduler.zig").SchedulerLabel;
const ComponentsFactory = @import("components.zig").Components;
const RegistryFactory = @import("registry.zig").Registry;
const query = @import("query/query.zig");

pub const AppOptions = struct {
    Context: type,
    Systems: []const System = &.{},
    SchedulerLabels: []const SchedulerLabel = &.{},
};

/// comptime struct used to encapsulate part of an application in modularized
/// and reusable way
/// includes:
/// - Components
/// - Systems
pub fn App(comptime options: AppOptions) type {
    return struct {
        pub const Components = options.Context.Components;
        pub const Entity = options.Context.Entity;
        pub const Registry = RegistryFactory(.{
            .Components = Components,
            .Entity = Entity,
        });

        allocator: std.mem.Allocator,
        registry: Registry,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
                .registry = Registry.init(alloc),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.registry.deinit();
        }

        /// use in systems to obtain a query. System signature should be like:
        /// fn systemExample(q: Query(.{.q = &.{typeA, *typeB}, .with = &.{typeC}}) !void {
        ///     ...
        /// }
        /// checkout QueryRequest for more information
        pub fn Query(comptime req: query.Request) type {
            return query.Factory(.{
                .request = req,
                .Entity = Entity,
                .Components = Components,
            });
        }
    };
}

test App {}
