// zlint-disable case-convention
const std = @import("std");
const System = @import("system.zig").System;
const StageLabel = @import("stage_label.zig").StageLabel;
const EntityOptions = @import("entity/entity.zig").EntityOptions;
const EntityTypeFactory = @import("entity/entity.zig").EntityTypeFactory;
const ComponentsFactory = @import("components.zig").Components;
const ResourcesFactory = @import("resource/resources.zig").Resources;
const WorldFactory = @import("world.zig").World;
const TypeStoreFactory = @import("resource/type_store.zig").TypeStore;
const EventStoreFactory = @import("event/event_store.zig").EventStore;
const EventsFactory = @import("event/events.zig").Events;
const BundleContext = @import("bundle/bundle.zig").BundleContext;
const Bundle = @import("bundle/bundle.zig").Bundle;
const app = @import("app.zig");
const app_events = @import("app_events.zig");
const ComponentConfig = @import("components.zig").ComponentConfig;

pub const AppContextBuilder = struct {
    const ConfigOverride = struct { type, ComponentConfig };
    bundle_builder: BundleContext.Builder = BundleContext.Builder.init(),
    entity: type = EntityTypeFactory(.medium),
    config_overrides: []const ConfigOverride = &.{},
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
    pub fn addComponentWithConfig(self: @This(), Component: type, config: ComponentConfig) @This() {
        var new = self;
        new.bundle_builder = new.bundle_builder.addComponentWithConfig(Component, config);
        return new;
    }
    /// Override a component's config.
    /// This is available only when building AppContext, not BundleContext intentionally, to avoid bundles
    /// overriding each other.
    /// results in a compile error if the component was never added.
    pub fn overrideComponentConfig(self: @This(), comptime Component: type, comptime config: ComponentConfig) @This() {
        var new = self;
        new.config_overrides = new.config_overrides ++ .{ConfigOverride{ Component, config }};
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
        var context: BundleContext = self.bundle_builder.build(self.entity);
        // Copy into a mutable array so we can override individual entries
        var configs: [context.ComponentConfigs.len]ComponentConfig =
            context.ComponentConfigs[0..].*;
        for (self.config_overrides) |override| {
            const Component, const config = override;
            if (std.mem.indexOfScalar(type, context.ComponentTypes, Component)) |idx| {
                configs[idx] = config;
            } else {
                @compileError("Component config override not possible: " ++
                    "component was never added! " ++
                    "Use `addComponentWithConfig` instead of `overrideComponentConfig`");
            }
        }
        const final_configs = configs;
        return app.AppContext(.{
            .Events = EventsFactory(context.EventTypes ++ app_events.appEventsSlice),
            .Resources = ResourcesFactory(context.ResourceTypes),
            .Components = ComponentsFactory(context.ComponentTypes, &final_configs),
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
    pub fn build(comptime self: @This(), allocator: std.mem.Allocator, io: std.Io) app.App(self.options) {
        const World = WorldFactory(.{
            .Components = self.options.Context.Components,
            .Entity = self.options.Context.Entity,
        });
        const TypeStore = TypeStoreFactory(.{
            .TypeHasher = self.options.Context.Resources,
        });
        const EventStore = EventStoreFactory(.{
            .Events = self.options.Context.Events,
        });
        return app.App(self.options){
            .allocator = allocator,
            .world = World.init(allocator),
            .resource_store = TypeStore.init(),
            .event_store = EventStore.init(allocator),
            .scheduler = null,
            .io = io,
        };
    }
};
