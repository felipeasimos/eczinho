const std = @import("std");
const System = @import("system.zig").System;
const ComponentsFactory = @import("components.zig").Components;
const ResourcesFactory = @import("resource/resources.zig").Resources;
const RegistryFactory = @import("registry.zig").Registry;
const TypeStoreFactory = @import("resource/type_store.zig").TypeStore;
const SchedulerFactory = @import("scheduler.zig").Scheduler;
const EntityTypeFactory = @import("entity.zig").EntityTypeFactory;
const query = @import("query/query.zig");
const commands = @import("commands/commands.zig");
const resource = @import("resource/resource.zig");

pub const AppContextOptions = struct {
    Components: type,
    Resources: type,
    Entity: type = EntityTypeFactory(.medium),
};

pub fn AppContext(comptime options: AppContextOptions) type {
    return struct {
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const Resources = options.Resources;
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

        /// use in systems to obtain a resource. System signature should be like:
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
        pub const Resources = options.Context.Resources;
        pub const Registry = RegistryFactory(.{
            .Components = Components,
            .Entity = Entity,
        });
        pub const TypeStore = TypeStoreFactory(.{
            .Resources = Resources,
        });
        pub const Scheduler = SchedulerFactory(.{
            .Context = options.Context,
            .Systems = options.Systems,
        });

        allocator: std.mem.Allocator,
        registry: Registry,
        store: TypeStore,
        scheduler: ?Scheduler = null,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
                .registry = Registry.init(alloc),
                .store = TypeStore.init(alloc),
            };
        }

        pub fn addResource(self: *@This(), value: anytype) !void {
            try self.store.insert(value);
        }

        pub fn run(self: *@This()) !void {
            self.startup();
            while (true) {
                self.scheduler.?.next();
            }
        }

        pub fn startup(self: *@This()) !void {
            self.scheduler = try Scheduler.init(&self.registry, &self.store);
        }

        pub fn deinit(self: *@This()) void {
            self.registry.deinit();
            self.store.deinit();
        }
    };
}

const TestAppContext = AppContext(.{
    .Resources = ResourcesFactory(&.{u7}),
    .Components = ComponentsFactory(&.{ u8, u64, u32 }),
});
const Query = TestAppContext.Query;
const Commands = TestAppContext.Commands;
const EntityId = TestAppContext.Entity;
const Resource = TestAppContext.Resource;

fn testSystemA(comms: Commands, res: Resource(u7)) !void {
    _ = comms.spawn()
        .add(@as(u8, 8))
        .add(@as(u64, 64));
    const ptr = res.getConst();
    try std.testing.expectEqual(@as(u7, 8), ptr.*);
    res.get().* = 7;
    try std.testing.expectEqual(@as(u7, 7), ptr.*);
}

fn testSystemB(comms: Commands, q: Query(.{ .q = &.{ *u8, ?u64, EntityId } })) !void {
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
}

test App {
    var app = App(.{
        .Context = TestAppContext,
        .Systems = &.{ System.init(.Startup, testSystemA), System.init(.Startup, testSystemB) },
    }).init(std.testing.allocator);
    defer app.deinit();
    try app.addResource(@as(u7, 8));
    try std.testing.expectEqual(0, app.registry.len());
    try app.startup();
    try std.testing.expectEqual(1, app.registry.len());
}
