const std = @import("std");
const System = @import("system.zig").System;
const SchedulerLabel = @import("scheduler.zig").SchedulerLabel;
const EntityOptions = @import("entity.zig").EntityOptions;
const EntityTypeFactory = @import("entity.zig").EntityTypeFactory;
const app = @import("app.zig");

pub const AppBuilder = struct {
    options: app.AppOptions = .{},
    pub fn init() @This() {
        return .{};
    }
    pub fn addComponent(self: @This(), Component: type) @This() {
        var new = self;
        new.options.Components = new.options.Components ++ Component;
        return new;
    }
    pub fn addComponents(self: @This(), Components: []const type) @This() {
        var new = self;
        for (Components) |Component| {
            new = new.addComponents(Component);
        }
        return new;
    }
    pub fn addSystem(self: @This(), label: SchedulerLabel, function: anytype) @This() {
        var new = self;
        new.options.Systems = new.options.Systems ++ System.init(function);
        new.options.SchedulerLabels = new.options.SchedulerLabels ++ label;
        return new;
    }
    pub fn addSystems(self: @This(), label: SchedulerLabel, functions: anytype) @This() {
        var new = self;
        for (functions) |function| {
            new = new.addSystem(label, function);
        }
        return new;
    }
    pub fn entity(self: @This(), options: EntityOptions) @This() {
        var new = self;
        new.options.Entity = EntityTypeFactory(options);
        return new;
    }
    pub fn getQuery(self: @This()) app.App(self).Query {
        return app.App(self).Query;
    }
    pub fn build(self: @This(), allocator: std.mem.Allocator) app.App(self) {
        return app.App(self).init(allocator);
    }
};

test AppBuilder {
    const typeA = struct { a: f32 };
    const test_app = AppBuilder.init()
        .addComponent(typeA)
        .addSystem(.Update, struct {
            pub fn execute() void {}
        }.execute)
        .build(std.testing.allocator);
    defer test_app.deinit();
}
