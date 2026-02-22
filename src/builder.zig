const std = @import("std");
const System = @import("system.zig").System;
const StageLabel = @import("stage_label.zig").StageLabel;
const EntityOptions = @import("entity.zig").EntityOptions;
const EntityTypeFactory = @import("entity.zig").EntityTypeFactory;
const ComponentsFactory = @import("components.zig").Components;
const ResourcesFactory = @import("resource/resources.zig").Resources;
const EventsFactory = @import("event/events.zig").Events;
const BundleContext = @import("bundle/bundle.zig").BundleContext;
const Bundle = @import("bundle/bundle.zig").Bundle;
const app = @import("app.zig");
const app_events = @import("app_events.zig");

pub const AppContextBuilder = struct {
    bundle_builder: BundleContext.Builder = BundleContext.Builder.init(),
    entity: type = EntityTypeFactory(.medium),
    pub fn init() @This() {
        return .{};
    }
    pub fn addBundle(self: @This(), bundle: Bundle) @This() {
        var new = self;
        new.bundle_builder = new.bundle_builder.addBundle(bundle);
        return new;
    }
    pub fn addBundles(self: @This(), bundles: []const Bundle) @This() {
        var new = self;
        new.bundle_builder = new.bundle_builder.addBundles(bundles);
        return new;
    }
    pub fn addComponent(self: @This(), Component: type) @This() {
        var new = self;
        new.bundle_builder = new.bundle_builder.addComponent(Component);
        return new;
    }
    pub fn addComponents(self: @This(), Components: []const type) @This() {
        var new = self;
        new.bundle_builder = new.bundle_builder.addComponents(Components);
        return new;
    }
    pub fn addResource(self: @This(), Resource: type) @This() {
        var new = self;
        new.bundle_builder = new.bundle_builder.addResource(Resource);
        return new;
    }
    pub fn addResources(self: @This(), Resources: []const type) @This() {
        var new = self;
        new.bundle_builder = new.bundle_builder.addResources(Resources);
        return new;
    }
    pub fn addEvent(self: @This(), Event: type) @This() {
        var new = self;
        new.bundle_builder = new.bundle_builder.addEvent(Event);
        return new;
    }
    pub fn addEvents(self: @This(), Events: []const type) @This() {
        var new = self;
        new.bundle_builder = new.bundle_builder.addEvents(Events);
        return new;
    }
    pub fn setEntityConfig(self: @This(), options: EntityOptions) @This() {
        var new = self;
        new.entity = EntityTypeFactory(options);
        return new;
    }
    pub fn build(self: @This()) type {
        var context: BundleContext = self.bundle_builder.build();
        for (self.bundle_builder.bundles) |bundle| {
            context = context.merge(bundle.ContextConstructor(self.entity));
        }
        return app.AppContext(.{
            .Events = EventsFactory(context.EventTypes ++ .{app_events.AppExit}),
            .Resources = ResourcesFactory(context.ResourceTypes),
            .Components = ComponentsFactory(context.ComponentTypes),
            .Bundles = context.Bundles,
            .Entity = self.entity,
        });
    }
};

pub const AppBuilder = struct {
    options: app.AppOptions,
    pub fn init(comptime ctx: type) @This() {
        const bundles = ctx.Bundles;
        var systems: []const type = &.{};
        var labels: []const StageLabel = &.{};
        for (bundles) |bundle| {
            const StructType = bundle.SystemsConstructor(ctx);
            var iter = Bundle.SystemIterator(ctx).init(bundle);
            inline while (iter.next()) |tuple| {
                const stage_label_name, const system_name = tuple;
                const stage_label = @field(StructType, stage_label_name);
                const function = @field(StructType, system_name);
                systems = systems ++ .{System(function, ctx)};
                labels = labels ++ .{stage_label};
            }
        }
        return .{
            .options = .{ .Context = ctx },
        };
    }
    pub fn addSystem(comptime self: @This(), comptime label: StageLabel, comptime function: anytype) @This() {
        var new = self;
        const system_slice: []const type = &.{System(function, self.options.Context)};
        const label_slice: []const StageLabel = &.{label};
        new.options.Systems = new.options.Systems ++ system_slice;
        new.options.Labels = new.options.Labels ++ label_slice;
        return new;
    }
    pub fn addSystems(self: @This(), label: StageLabel, functions: anytype) @This() {
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
    const Transform = @import("bundle/core/transform.zig").Transform;
    const typeA = struct { a: f32 };
    const typeB = struct { a: u32 };
    const entity_config: EntityOptions = .{ .index_bits = 10, .version_bits = 11 };
    const Context = AppContextBuilder.init()
        .addComponent(typeA)
        .addComponents(&.{typeB})
        .addBundle(Transform)
        .setEntityConfig(entity_config)
        .build();
    try std.testing.expect(Context.Components.isComponent(typeA));
    try std.testing.expect(Context.Components.isComponent(typeB));
    try std.testing.expectEqual(EntityTypeFactory(entity_config), Context.Entity);
}

test AppBuilder {
    const Position = @import("bundle/core/transform.zig").Position;
    const Rotation = @import("bundle/core/transform.zig").Rotation;
    const Transform = @import("bundle/core/transform.zig").Transform;
    const Hierarchy = @import("bundle/core/hierarchy.zig").Hierarchy;
    const ChildConstructor = @import("bundle/core/hierarchy.zig").ChildConstructor;
    const ParentConstructor = @import("bundle/core/hierarchy.zig").ParentConstructor;

    const typeA = struct { a: f32 };
    const typeB = struct { a: u32 };

    const Context = AppContextBuilder.init()
        .addBundle(Transform)
        .addBundle(Hierarchy)
        .addComponent(typeA)
        .addComponents(&.{typeB})
        .build();

    try std.testing.expect(Context.Components.isComponent(Position));
    try std.testing.expect(Context.Components.isComponent(Rotation));
    try std.testing.expect(Context.Components.isComponent(ChildConstructor(Context.Entity)));
    try std.testing.expect(Context.Components.isComponent(ParentConstructor(Context.Entity)));

    const Query = Context.Query;

    var test_app = AppBuilder.init(Context)
        .addSystem(.Update, struct {
            pub fn execute(_: Query(.{ .q = &.{ typeA, *typeB } })) void {}
        }.execute)
        .build(std.testing.allocator);
    defer test_app.deinit();
}
