const std = @import("std");
const System = @import("system.zig").System;
const ComponentsFactory = @import("components.zig").Components;
const RegistryFactory = @import("registry.zig").Registry;
const SchedulerFactory = @import("scheduler.zig").Scheduler;
const EntityTypeFactory = @import("entity.zig").EntityTypeFactory;
const SchedulerLabel = @import("scheduler.zig").SchedulerLabel;
const query = @import("query/query.zig");
const commands = @import("commands/commands.zig");
const resource = @import("resource/resource.zig");
const event = @import("event/event.zig");
const removed = @import("removed/removed.zig");
const app_events = @import("app_events.zig");
const Tick = @import("types.zig").Tick;

pub const AppContextOptions = struct {
    Components: type,
    Resources: type,
    Events: type,
    Entity: type = EntityTypeFactory(.medium),
};

pub fn AppContext(comptime options: AppContextOptions) type {
    return struct {
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const Resources = options.Resources;
        pub const Events = options.Events;
        pub const TypeStore = resource.TypeStore(.{
            .Resources = Resources,
        });
        /// use in systems to obtain a query. System signature should be like:
        /// fn systemExample(q: Query(.{.q = &.{typeA, *typeB}, .with = &.{typeC}}), ...) !void {
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
        /// use in systems to obtain a Commands object. System signature should be like:
        /// fn systemExample(comms: Commands, ...) !void {
        ///     ...
        /// }
        pub const Commands = commands.Commands(.{
            .Components = Components,
            .Entity = Entity,
        });

        /// use in systems to obtain access to resource. System signature should be like:
        /// fn systemExample(q: Resource(typeA), ...) !void {
        ///     ...
        /// }
        /// returned handle can access resource using get() *T or getConst() *const T
        pub fn Resource(comptime T: type) type {
            return resource.Resource(.{
                .TypeStore = TypeStore,
                .T = T,
            });
        }

        /// use in systems to obtain a event writer or an event reader. System signature should be like:
        /// fn systemExample(w: EventWriter(u64), r: EventReader(u8), ...) !void {
        ///     ...
        /// }
        pub fn EventWriter(comptime T: type) type {
            return event.EventWriter(.{
                .Events = Events,
                .T = T,
            });
        }
        pub fn EventReader(comptime T: type) type {
            return event.EventReader(.{
                .Events = Events,
                .T = T,
            });
        }

        /// use in systems to return entities which had components recently removed (in the last schedule run). System signature should be like:
        /// fn systemExample(r: Removed(u64), ...) !void {
        ///     ...
        /// }
        pub fn Removed(comptime T: type) type {
            return removed.Removed(.{
                .Components = Components,
                .Entity = Entity,
                .T = T,
                .Tick = Tick,
            });
        }
    };
}

pub const AppOptions = struct {
    Context: type,
    Systems: []const type = &.{},
    Labels: []const SchedulerLabel = &.{},
};

/// comptime struct used to encapsulate part of an application in modularized
/// and reusable way
/// includes:
/// - Components types
/// - Systems
/// - Event types
/// - Resources
pub fn App(comptime options: AppOptions) type {
    return struct {
        pub const Components = options.Context.Components;
        pub const Entity = options.Context.Entity;
        pub const Resources = options.Context.Resources;
        pub const Events = options.Context.Events;
        pub const Registry = RegistryFactory(.{
            .Components = Components,
            .Entity = Entity,
        });
        pub const TypeStore = resource.TypeStore(.{
            .Resources = Resources,
        });
        pub const EventStore = event.EventStore(.{
            .Events = Events,
        });
        pub const RemovedLog = removed.RemovedLog(.{
            .Components = Components,
            .Entity = Entity,
        });
        pub const Scheduler = SchedulerFactory(.{
            .Context = options.Context,
            .Systems = options.Systems,
            .Labels = options.Labels,
        });

        allocator: std.mem.Allocator,
        registry: Registry,
        resource_store: TypeStore,
        event_store: EventStore,
        scheduler: ?Scheduler = null,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
                .registry = Registry.init(alloc),
                .resource_store = TypeStore.init(alloc),
                .event_store = EventStore.init(alloc),
            };
        }

        fn shouldExit(self: *@This()) bool {
            return self.event_store.total(app_events.AppExit) != 0;
        }
        pub fn run(self: *@This()) !void {
            try self.startup();
            while (!self.shouldExit()) {
                try self.scheduler.?.run();
            }
        }

        pub fn startup(self: *@This()) !void {
            self.scheduler = try Scheduler.init(
                &self.registry,
                &self.resource_store,
                &self.event_store,
            );
        }

        pub fn insert(self: *@This(), value: anytype) !void {
            try self.resource_store.insert(value);
        }

        pub fn deinit(self: *@This()) void {
            self.registry.deinit();
            self.resource_store.deinit();
            self.event_store.deinit();
            if (self.scheduler) |sch| {
                sch.deinit();
            }
        }
    };
}
const TestAppContext = AppContext(.{
    .Resources = resource.Resources(&.{u7}),
    .Components = ComponentsFactory(&.{ u8, u64, u32 }),
    .Events = event.Events(&.{u4}),
});
const Query = TestAppContext.Query;
const Commands = TestAppContext.Commands;
const EntityId = TestAppContext.Entity;
const Resource = TestAppContext.Resource;
const EventReader = TestAppContext.EventReader;
const EventWriter = TestAppContext.EventWriter;

fn testSystemA(comms: Commands, res: Resource(u7), writer: EventWriter(u4)) !void {
    _ = comms.spawn()
        .add(@as(u8, 8))
        .add(@as(u64, 64));
    const ptr = res.getConst();
    try std.testing.expectEqual(@as(u7, 8), ptr.*);
    res.get().* = 7;
    try std.testing.expectEqual(@as(u7, 7), ptr.*);
    writer.write(@as(u4, 3));
}

fn testSystemB(comms: Commands, q: Query(.{ .q = &.{ *u8, ?u64, EntityId } }), reader: EventReader(u4)) !void {
    _ = comms;
    var iter = q.iter();
    while (iter.next()) |tuple| {
        const _u8, const _u64, const id = tuple;
        try std.testing.expectEqual(*u8, @TypeOf(_u8));
        try std.testing.expectEqual(?u64, @TypeOf(_u64));
        try std.testing.expectEqual(EntityId, @TypeOf(id));

        try std.testing.expectEqual(8, _u8.*);
        try std.testing.expectEqual(64, _u64.?);
    }
    _ = reader;
    // try std.testing.expectEqual(1, reader.remaining());
    // try std.testing.expectEqual(@as(u4, 3), reader.read());
}

test App {
    var app = App(.{
        .Context = TestAppContext,
        .Systems = &.{ System(testSystemA, TestAppContext), System(testSystemB, TestAppContext) },
        .Labels = &.{ .Startup, .Startup },
    }).init(std.testing.allocator);
    defer app.deinit();

    try app.resource_store.insert(@as(u7, 8));
    try std.testing.expectEqual(0, app.registry.len());
    try app.startup();
    try app.scheduler.?.run();
    try std.testing.expectEqual(1, app.registry.len());
}
