const std = @import("std");
const WorldFactory = @import("world.zig").World;
const SchedulerFactory = @import("scheduler.zig").Scheduler;
const EntityTypeFactory = @import("entity/entity.zig").EntityTypeFactory;
const StageLabel = @import("stage_label.zig").StageLabel;
const query = @import("query/query.zig");
const commands = @import("commands/commands.zig");
const resource = @import("resource/resource.zig");
const event = @import("event/event.zig");
const removed = @import("removed/removed.zig");
const app_events = @import("app_events.zig");
const Tick = @import("types.zig").Tick;
const Bundle = @import("bundle/bundle.zig").Bundle;
const dense_storage = @import("storage/dense_storage.zig");

pub const AppContextOptions = struct {
    Components: type,
    Resources: type,
    Events: type,
    Bundles: []const Bundle = &.{},
    Entity: type = EntityTypeFactory(.medium),
    DenseStorageConfig: dense_storage.DenseStorageConfig,
};

pub fn AppContext(comptime options: AppContextOptions) type {
    return struct {
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const Resources = options.Resources;
        pub const Events = options.Events;
        pub const Bundles = options.Bundles;
        pub const DenseStorageConfig = options.DenseStorageConfig;

        /// use in systems to obtain access to the whole resource store
        /// fn systemExample(store: *ResourceStore(typeA), ...) !void {
        ///     ...
        /// }
        pub const ResourceStore = resource.TypeStore(.{
            .TypeHasher = Resources,
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
                .World = GetWorldType(),
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
                .TypeStore = ResourceStore,
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

        /// use in systems to return entities which had components recently removed (in the last schedule run).
        /// System signature should be like:
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

        pub fn GetWorldType() type {
            return WorldFactory(.{
                .Entity = Entity,
                .Components = Components,
                .DenseStorageConfig = DenseStorageConfig,
            });
        }
    };
}

pub const AppOptions = struct {
    Context: type,
    Systems: []const type = &.{},
    Labels: []const StageLabel = &.{},
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
        pub const World = WorldFactory(.{
            .Components = Components,
            .Entity = Entity,
            .DenseStorageConfig = options.Context.DenseStorageConfig,
        });
        pub const TypeStore = resource.TypeStore(.{
            .TypeHasher = Resources,
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
        world: World,
        resource_store: TypeStore,
        event_store: EventStore,
        scheduler: ?Scheduler = null,
        io: std.Io,

        fn shouldExit(self: *@This()) bool {
            return self.event_store.total(app_events.AppExit) != 0;
        }
        pub fn run(self: *@This()) !void {
            try self.startup();
            while (!self.shouldExit()) {
                try self.runOne();
            }
        }
        pub fn runOne(self: *@This()) !void {
            try self.scheduler.?.run();
        }

        pub fn startup(self: *@This()) !void {
            self.scheduler = try Scheduler.init(
                &self.world,
                &self.resource_store,
                &self.event_store,
            );
        }

        pub fn insertResource(self: *@This(), value: anytype) void {
            self.resource_store.insert(value);
        }

        pub fn deinit(self: *@This()) void {
            self.world.deinit();
            self.resource_store.deinit();
            self.event_store.deinit();
            if (self.scheduler) |sch| {
                sch.deinit();
            }
        }
    };
}
