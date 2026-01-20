const std = @import("std");
const System = @import("system.zig").System;
const SchedulerLabel = @import("scheduler.zig").SchedulerLabel;
const ComponentsFactory = @import("components.zig").Components;
const RegistryFactory = @import("registry.zig").Registry;
const SchedulerFactory = @import("scheduler.zig").Scheduler;
const EntityTypeFactory = @import("entity.zig").EntityTypeFactory;
const query = @import("query/query.zig");

pub const AppContextOptions = struct {
    Components: type,
    Entity: type = EntityTypeFactory(.medium),
};

pub fn AppContext(comptime options: AppContextOptions) type {
    return struct {
        pub const Entity = options.Entity;
        pub const Components = options.Components;
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

pub const AppOptions = struct {
    Context: type,
    Systems: []const System = &.{},
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
        pub const Scheduler = SchedulerFactory(.{
            .Context = options.Context,
            .Systems = options.Systems,
        });

        allocator: std.mem.Allocator,
        registry: Registry,
        scheduler: Scheduler,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
                .registry = Registry.init(alloc),
                .scheduler = undefined,
            };
        }

        pub fn run(self: *@This()) !void {
            self.scheduler = Scheduler.init(self.registry);
            self.scheduler.run();
        }

        pub fn deinit(self: *@This()) void {
            self.registry.deinit();
        }
    };
}

const TestAppContext = AppContext(.{
    .Components = ComponentsFactory(&.{ u8, u64, u32 }),
});
const Query = TestAppContext.Query;

fn testSystemA(q: Query(.{ .q = &.{ *u8, ?u64 } })) void {
    var iter = q.iter();
    while (iter.next()) |tuple| {
        _ = tuple;
    }
}

fn testSystemB(q: Query(.{ .q = &.{ *u8, ?u64 } })) void {
    var iter = q.iter();
    while (iter.next()) |tuple| {
        _ = tuple;
    }
}

test App {
    var app = App(.{
        .Context = TestAppContext,
        .Systems = &.{ System.init(.Update, testSystemA), System.init(.Startup, testSystemB) },
    }).init(std.testing.allocator);
    defer app.deinit();
}
