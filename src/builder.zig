const std = @import("std");
const System = @import("system.zig").System;
const SchedulerLabel = @import("scheduler.zig").SchedulerLabel;
const EntityOptions = @import("entity.zig").EntityOptions;
const EntityTypeFactory = @import("entity.zig").EntityTypeFactory;
const ComponentsFactory = @import("components.zig").Components;
const query = @import("query/query.zig");
const app = @import("app.zig");

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

pub const AppContextBuilder = struct {
    components: []const type = &.{},
    entity: type = EntityTypeFactory(.medium),
    pub fn init() @This() {
        return .{};
    }
    pub fn addComponent(self: @This(), Component: type) @This() {
        var new = self;
        new.components = new.components ++ .{Component};
        return new;
    }
    pub fn addComponents(self: @This(), Components: []const type) @This() {
        var new = self;
        for (Components) |Component| {
            new = new.addComponent(Component);
        }
        return new;
    }
    pub fn setEntityConfig(self: @This(), options: EntityOptions) @This() {
        var new = self;
        new.entity = EntityTypeFactory(options);
        return new;
    }
    pub fn build(self: @This()) type {
        return AppContext(.{
            .Components = ComponentsFactory(self.components),
            .Entity = self.entity,
        });
    }
};

pub const AppBuilder = struct {
    options: app.AppOptions,
    pub fn init(ctx: type) @This() {
        return .{
            .options = .{ .Context = ctx },
        };
    }
    pub fn addSystem(comptime self: @This(), label: SchedulerLabel, comptime function: anytype) @This() {
        var new = self;
        const system_slice: []const System = &.{System.init(function)};
        new.options.Systems = new.options.Systems ++ system_slice;
        const label_slice: []const SchedulerLabel = &.{label};
        new.options.SchedulerLabels = new.options.SchedulerLabels ++ label_slice;
        return new;
    }
    pub fn addSystems(self: @This(), label: SchedulerLabel, functions: anytype) @This() {
        var new = self;
        for (functions) |function| {
            new = new.addSystem(label, function);
        }
        return new;
    }
    pub fn getQuery(self: @This()) app.App(self).Query {
        return app.App(self).Query;
    }
    pub fn build(comptime self: @This(), allocator: std.mem.Allocator) app.App(self.options) {
        return app.App(self.options).init(allocator);
    }
};

test AppContextBuilder {
    const typeA = struct { a: f32 };
    const typeB = struct { a: u32 };
    const entity_config: EntityOptions = .{ .index_bits = 10, .version_bits = 11 };
    const Context = AppContextBuilder.init()
        .addComponent(typeA)
        .addComponents(&.{typeB})
        .setEntityConfig(entity_config)
        .build();
    try std.testing.expect(Context.Components.isComponent(typeA));
    try std.testing.expect(Context.Components.isComponent(typeB));
    try std.testing.expectEqual(EntityTypeFactory(entity_config), Context.Entity);
}

test AppBuilder {
    const typeA = struct { a: f32 };
    const typeB = struct { a: u32 };
    const Context = AppContextBuilder.init()
        .addComponent(typeA)
        .addComponents(&.{typeB})
        .build();
    const Query = Context.Query;
    var test_app = AppBuilder.init(Context)
        .addSystem(.Update, struct {
            pub fn execute(_: Query(.{ .q = &.{ typeA, *typeB } })) void {}
        }.execute)
        .build(std.testing.allocator);
    defer test_app.deinit();
}
