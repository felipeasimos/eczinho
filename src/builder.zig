// zlint-disable case-convention
const std = @import("std");
const System = @import("system/system.zig").System;
const StageLabel = @import("scheduler/stage_label.zig").StageLabel;
const EntityOptions = @import("entity/entity.zig").EntityOptions;
const EntityTypeFactory = @import("entity/entity.zig").EntityTypeFactory;
const ComponentsFactory = @import("components.zig").Components;
const ResourcesFactory = @import("resource/resources.zig").Resources;
const TypeStoreFactory = @import("resource/type_store.zig").TypeStore;
const EventStoreFactory = @import("event/event_store.zig").EventStore;
const EventsFactory = @import("event/events.zig").Events;
const BundleContext = @import("bundle/bundle.zig").BundleContext;
const Bundle = @import("bundle/bundle.zig").Bundle;
const app = @import("app.zig");
const app_events = @import("app_events.zig");
const ComponentConfig = @import("components.zig").ComponentConfig;
const dense_storage = @import("storage/dense_storage.zig");

pub const AppContextBuilder = struct {
    const ConfigOverride = struct { type, ComponentConfig };
    bundle_builder: BundleContext.Builder = BundleContext.Builder.init(),
    entity: type = EntityTypeFactory(.medium),
    config_overrides: []const ConfigOverride = &.{},
    dense_storage_config: ?dense_storage.DenseStorageConfig = null,
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
    pub fn setDenseStorageConfig(self: @This(), config: dense_storage.DenseStorageConfig) @This() {
        var new = self;
        new.dense_storage_config = config;
        return new;
    }
    /// duplicated bundles are silently ignored
    /// duplicated components, reosurces and events (in different bundles)
    /// will result in a compile time error
    pub fn build(self: @This()) type {
        const context: BundleContext = self.bundle_builder.build();
        const merged_context = mergeWithBundles(context, self.entity);
        const validated_context = checkForDuplicates(merged_context);
        // Copy into a mutable array so we can override individual entries
        var configs: [validated_context.ComponentConfigs.len]ComponentConfig =
            validated_context.ComponentConfigs[0..].*;
        for (self.config_overrides) |override| {
            const Component, const config = override;
            if (std.mem.indexOfScalar(type, validated_context.ComponentTypes, Component)) |idx| {
                configs[idx] = config;
            } else {
                @compileError("Component config override not possible: " ++
                    "component was never added! " ++
                    "Use `addComponentWithConfig` instead of `overrideComponentConfig`");
            }
        }
        const final_configs = configs;
        const dense_storage_config = self.dense_storage_config orelse dense_storage.DenseStorageConfig{ .Tables = .{} };

        return app.AppContext(.{
            .Events = EventsFactory(validated_context.EventTypes ++ app_events.appEventsSlice),
            .Resources = ResourcesFactory(validated_context.ResourceTypes),
            .Components = ComponentsFactory(validated_context.ComponentTypes, &final_configs),
            .Bundles = validated_context.Bundles,
            .Entity = self.entity,
            .DenseStorageConfig = dense_storage_config,
        });
    }
    /// recursively go through given bundles, to get a complete list of bundles
    /// without duplicates
    /// `current_bundles` should be an empty list initially
    fn getCompleteListOfBundles(
        current_bundles: []const Bundle,
        additional_bundles: []const Bundle,
        comptime Entity: type,
    ) []const Bundle {
        if (current_bundles.len == 0 and additional_bundles.len == 0) {
            return &.{};
        }
        var final_bundles: []const Bundle = current_bundles;
        // attach first-level bundles to this one
        for (additional_bundles) |bundle| {
            if (!Bundle.containsBundle(final_bundles, bundle)) {
                final_bundles = final_bundles ++ .{bundle};
                const bundle_context = bundle.ContextConstructor(Entity);
                final_bundles = getCompleteListOfBundles(final_bundles, bundle_context.Bundles, Entity);
            }
        }
        return final_bundles;
    }
    fn mergeWithBundles(bundle: BundleContext, comptime Entity: type) BundleContext {
        const bundles = getCompleteListOfBundles(&.{}, bundle.Bundles, Entity);
        var merged_context = bundle;
        merged_context.Bundles = bundles;
        for (bundles) |b| {
            const bundle_context = b.ContextConstructor(Entity);
            merged_context.ComponentTypes = merged_context.ComponentTypes ++ bundle_context.ComponentTypes;
            merged_context.ComponentConfigs = merged_context.ComponentConfigs ++ bundle_context.ComponentConfigs;
            merged_context.ResourceTypes = merged_context.ResourceTypes ++ bundle_context.ResourceTypes;
            merged_context.EventTypes = merged_context.EventTypes ++ bundle_context.EventTypes;
        }
        return merged_context;
    }
    fn checkForDuplicates(bundle: BundleContext) BundleContext {
        var context: BundleContext = .{
            .Bundles = bundle.Bundles,
        };
        for (bundle.ComponentTypes, bundle.ComponentConfigs) |Component, config| {
            if (std.mem.indexOfScalar(type, context.ComponentTypes, Component) == null) {
                context.ComponentTypes = context.ComponentTypes ++ .{Component};
                context.ComponentConfigs = context.ComponentConfigs ++ .{config};
            } else {
                @compileError("Component of type '" ++ @typeName(Component) ++ "' was already registered");
            }
        }
        for (bundle.ResourceTypes) |Resource| {
            if (std.mem.indexOfScalar(type, context.ResourceTypes, Resource) == null) {
                context.ResourceTypes = context.ResourceTypes ++ .{Resource};
            } else {
                @compileError("Resource of type '" ++ @typeName(Resource) ++ "' was already registered");
            }
        }
        for (bundle.EventTypes) |Event| {
            if (std.mem.indexOfScalar(type, context.EventTypes, Event) == null) {
                context.EventTypes = context.EventTypes ++ .{Event};
            } else {
                @compileError("Event of type '" ++ @typeName(Event) ++ "' was already registered");
            }
        }
        return context;
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
    pub fn build(comptime self: @This(), allocator: std.mem.Allocator, io: std.Io) !app.App(self.options) {
        const World = self.options.Context.GetWorldType();
        const TypeStore = TypeStoreFactory(.{
            .TypeHasher = self.options.Context.Resources,
        });
        const EventStore = EventStoreFactory(.{
            .Events = self.options.Context.Events,
        });
        return app.App(self.options){
            .allocator = allocator,
            .world = try World.init(allocator),
            .resource_store = TypeStore.init(),
            .event_store = EventStore.init(allocator),
            .scheduler = null,
            .io = io,
        };
    }
};
