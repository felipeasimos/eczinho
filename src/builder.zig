const std = @import("std");
const System = @import("system.zig").System;
const SchedulerLabel = @import("scheduler.zig").SchedulerLabel;
const EntityOptions = @import("entity.zig").EntityOptions;
const EntityTypeFactory = @import("entity.zig").EntityTypeFactory;
const ComponentsFactory = @import("components.zig").Components;
const app = @import("app.zig");

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
    pub fn getQuery(self: @This()) app.AppContext(self).Query {
        return app.AppContext(self).Query;
    }
    pub fn build(self: @This()) type {
        return app.AppContext(.{
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
    pub fn addSystem(comptime self: @This(), comptime label: SchedulerLabel, comptime function: anytype) @This() {
        var new = self;
        const system_slice: []const System = &.{System.init(label, function)};
        new.options.Systems = new.options.Systems ++ system_slice;
        return new;
    }
    pub fn addSystems(self: @This(), label: SchedulerLabel, functions: anytype) @This() {
        var new = self;
        for (functions) |function| {
            new = new.addSystem(label, function);
        }
        return new;
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
