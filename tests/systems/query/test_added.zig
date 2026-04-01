const std = @import("std");
const eczinho = @import("eczinho");

test "check if chunked component was just added" {
    const ComponentA = u64;
    const ComponentB = u32;
    const AddedTicks = u32;
    const NotAddedTicks = u31;
    const Context = eczinho.AppContextBuilder.init()
        .addComponent(ComponentA)
        .addComponentWithConfig(ComponentB, .{
            .storage_type = .Dense,
            .track_metadata = .{
                .added = true,
                .changed = false,
                .removed = false,
            },
        })
        .addResource(AddedTicks)
        .addResource(NotAddedTicks)
        .build();

    const Resource = Context.Resource;
    const ResourceStore = Context.ResourceStore;
    const Commands = Context.Commands;
    const Query = Context.Query;
    const Entity = Context.Entity;

    var app = eczinho.AppBuilder.init(Context)
        .addSystem(.Startup, (struct {
            pub fn addResource(store: *ResourceStore) !void {
                store.insert(@as(AddedTicks, 0));
                store.insert(@as(NotAddedTicks, 0));
            }
        }).addResource)
        .addSystem(.Startup, (struct {
            pub fn spawnEntity(comms: Commands) void {
                _ = comms.spawn().add(@as(ComponentA, 5));
            }
        }).spawnEntity)
        .addSystem(.Update, (struct {
            pub fn checkIfNotAdded(
                res: Resource(NotAddedTicks),
                q: Query(.{ .q = &.{ComponentA}, .added = &.{ComponentB} }),
            ) void {
                if (q.len() == 0) {
                    res.get().* += 1;
                }
            }
        }).checkIfNotAdded)
        .addSystem(.Update, (struct {
            pub fn checkIfAdded(
                res: Resource(AddedTicks),
                q: Query(.{ .q = &.{ComponentA}, .added = &.{ComponentB} }),
            ) void {
                if (q.len() > 0) {
                    res.get().* += 1;
                }
            }
        }).checkIfAdded)
        .addSystem(.Update, (struct {
            pub fn addIfNotPresent(
                comms: Commands,
                q: Query(.{ .q = &.{Entity}, .without = &.{ComponentB}, .with = &.{ComponentA} }),
            ) void {
                if (q.peek()) |tuple| {
                    const entt = tuple[0];
                    _ = comms.entity(entt).add(@as(ComponentB, 123));
                }
            }
        }).addIfNotPresent)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    // spawn entity without component
    try app.startup();

    try std.testing.expectEqual(0, app.resource_store.clone(AddedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(NotAddedTicks));

    // add component to entity
    try app.runOne();
    try std.testing.expectEqual(1, app.resource_store.clone(NotAddedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(AddedTicks));

    // deferred apply at the beginning of the run actually applies changes
    // added ticks is updated
    try app.runOne();
    try std.testing.expectEqual(1, app.resource_store.clone(NotAddedTicks));
    try std.testing.expectEqual(1, app.resource_store.clone(AddedTicks));

    // now that it was added, the .added query no longer applies
    // not added ticks is updated
    try app.runOne();
    try std.testing.expectEqual(2, app.resource_store.clone(NotAddedTicks));
    try std.testing.expectEqual(1, app.resource_store.clone(AddedTicks));
}

test "check if sparse component was just added" {
    const ComponentA = u64;
    const ComponentB = u32;
    const AddedTicks = u32;
    const NotAddedTicks = u31;
    const Context = eczinho.AppContextBuilder.init()
        .addComponentWithConfig(ComponentA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = true,
                .changed = false,
                .removed = false,
            },
        })
        .addComponentWithConfig(ComponentB, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = true,
                .changed = false,
                .removed = false,
            },
        })
        .addResource(AddedTicks)
        .addResource(NotAddedTicks)
        .build();

    const Resource = Context.Resource;
    const ResourceStore = Context.ResourceStore;
    const Commands = Context.Commands;
    const Query = Context.Query;
    const Entity = Context.Entity;

    var app = eczinho.AppBuilder.init(Context)
        .addSystem(.Startup, (struct {
            pub fn addResource(store: *ResourceStore) !void {
                store.insert(@as(AddedTicks, 0));
                store.insert(@as(NotAddedTicks, 0));
            }
        }).addResource)
        .addSystem(.Startup, (struct {
            pub fn spawnEntity(comms: Commands) void {
                _ = comms.spawn().add(@as(ComponentA, 5));
            }
        }).spawnEntity)
        .addSystem(.Update, (struct {
            pub fn checkIfNotAdded(
                res: Resource(NotAddedTicks),
                q: Query(.{ .q = &.{ComponentA}, .added = &.{ComponentB} }),
            ) void {
                if (q.len() == 0) {
                    res.get().* += 1;
                }
            }
        }).checkIfNotAdded)
        .addSystem(.Update, (struct {
            pub fn checkIfAdded(
                res: Resource(AddedTicks),
                q: Query(.{ .q = &.{ComponentA}, .added = &.{ComponentB} }),
            ) void {
                if (q.len() > 0) {
                    res.get().* += 1;
                }
            }
        }).checkIfAdded)
        .addSystem(.Update, (struct {
            pub fn addIfNotPresent(
                comms: Commands,
                q: Query(.{ .q = &.{Entity}, .without = &.{ComponentB}, .with = &.{ComponentA} }),
            ) void {
                if (q.peek()) |tuple| {
                    const entt = tuple[0];
                    _ = comms.entity(entt).add(@as(ComponentB, 123));
                }
            }
        }).addIfNotPresent)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    // spawn entity without component
    try app.startup();

    try std.testing.expectEqual(0, app.resource_store.clone(AddedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(NotAddedTicks));

    // add component to entity
    try app.runOne();
    try std.testing.expectEqual(1, app.resource_store.clone(NotAddedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(AddedTicks));

    // deferred apply at the beginning of the run actually applies changes
    // added ticks is updated
    try app.runOne();
    try std.testing.expectEqual(1, app.resource_store.clone(NotAddedTicks));
    try std.testing.expectEqual(1, app.resource_store.clone(AddedTicks));

    // now that it was added, the .added query no longer applies
    // not added ticks is updated
    try app.runOne();
    try std.testing.expectEqual(2, app.resource_store.clone(NotAddedTicks));
    try std.testing.expectEqual(1, app.resource_store.clone(AddedTicks));
}
