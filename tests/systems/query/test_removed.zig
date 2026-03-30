const std = @import("std");
const eczinho = @import("eczinho");

test "check if chunked component was just removed" {
    const ComponentA = u64;
    const ComponentB = u32;
    const RemovedTicks = u32;
    const NotRemovedTicks = u31;
    const Context = eczinho.AppContextBuilder.init()
        .addComponent(ComponentA)
        .addComponent(ComponentB)
        .addResource(RemovedTicks)
        .addResource(NotRemovedTicks)
        .build();

    const Resource = Context.Resource;
    const ResourceStore = Context.ResourceStore;
    const Commands = Context.Commands;
    const Query = Context.Query;
    const Entity = Context.Entity;
    const Removed = Context.Removed;

    var app = eczinho.AppBuilder.init(Context)
        .addSystem(.Startup, (struct {
            pub fn addResource(store: *ResourceStore) !void {
                store.insert(@as(RemovedTicks, 0));
                store.insert(@as(NotRemovedTicks, 0));
            }
        }).addResource)
        .addSystem(.Startup, (struct {
            pub fn spawnEntity(comms: Commands) void {
                _ = comms.spawn()
                    .add(@as(ComponentA, 5))
                    .add(@as(ComponentB, 6));
            }
        }).spawnEntity)
        .addSystem(.Update, (struct {
            pub fn checkIfNotRemoved(
                res: Resource(NotRemovedTicks),
                removed: Removed(ComponentB),
            ) void {
                if (removed.readOne() == null) {
                    res.get().* += 1;
                }
            }
        }).checkIfNotRemoved)
        .addSystem(.Update, (struct {
            pub fn checkIfRemoved(
                res: Resource(RemovedTicks),
                removed: Removed(ComponentB),
            ) void {
                if (removed.readOne() != null) {
                    res.get().* += 1;
                }
            }
        }).checkIfRemoved)
        .addSystem(.Update, (struct {
            pub fn removeIfPresent(
                comms: Commands,
                q: Query(.{ .q = &.{Entity}, .with = &.{ ComponentB, ComponentA } }),
            ) void {
                if (q.peek()) |tuple| {
                    const entt = tuple[0];
                    _ = comms.entity(entt).remove(ComponentB);
                }
            }
        }).removeIfPresent)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    // spawn entity with component
    try app.startup();

    try std.testing.expectEqual(0, app.resource_store.clone(RemovedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(NotRemovedTicks));

    // remove component from entity
    try app.runOne();
    try std.testing.expectEqual(1, app.resource_store.clone(NotRemovedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(RemovedTicks));

    // deferred apply at the beginning of the run actually applies changes
    // removed logs is written now, which means it can be read in the next tick
    try app.runOne();
    try std.testing.expectEqual(2, app.resource_store.clone(NotRemovedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(RemovedTicks));

    // now the removed log can be read
    try app.runOne();
    try std.testing.expectEqual(2, app.resource_store.clone(NotRemovedTicks));
    try std.testing.expectEqual(1, app.resource_store.clone(RemovedTicks));
}

test "check if sparse component was just removed" {
    const ComponentA = u64;
    const ComponentB = u32;
    const RemovedTicks = u32;
    const NotRemovedTicks = u31;
    const Context = eczinho.AppContextBuilder.init()
        .addComponentWithConfig(ComponentA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
        .addComponentWithConfig(ComponentB, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
            },
        })
        .addResource(RemovedTicks)
        .addResource(NotRemovedTicks)
        .build();

    const Resource = Context.Resource;
    const ResourceStore = Context.ResourceStore;
    const Commands = Context.Commands;
    const Query = Context.Query;
    const Entity = Context.Entity;
    const Removed = Context.Removed;

    var app = eczinho.AppBuilder.init(Context)
        .addSystem(.Startup, (struct {
            pub fn addResource(store: *ResourceStore) !void {
                store.insert(@as(RemovedTicks, 0));
                store.insert(@as(NotRemovedTicks, 0));
            }
        }).addResource)
        .addSystem(.Startup, (struct {
            pub fn spawnEntity(comms: Commands) void {
                _ = comms.spawn()
                    .add(@as(ComponentA, 5))
                    .add(@as(ComponentB, 6));
            }
        }).spawnEntity)
        .addSystem(.Update, (struct {
            pub fn checkIfNotRemoved(
                res: Resource(NotRemovedTicks),
                removed: Removed(ComponentB),
            ) void {
                if (removed.readOne() == null) {
                    res.get().* += 1;
                }
            }
        }).checkIfNotRemoved)
        .addSystem(.Update, (struct {
            pub fn checkIfRemoved(
                res: Resource(RemovedTicks),
                removed: Removed(ComponentB),
            ) void {
                if (removed.readOne() != null) {
                    res.get().* += 1;
                }
            }
        }).checkIfRemoved)
        .addSystem(.Update, (struct {
            pub fn removeIfPresent(
                comms: Commands,
                q: Query(.{ .q = &.{Entity}, .with = &.{ ComponentB, ComponentA } }),
            ) void {
                if (q.peek()) |tuple| {
                    const entt = tuple[0];
                    _ = comms.entity(entt).remove(ComponentB);
                }
            }
        }).removeIfPresent)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    // spawn entity with component
    try app.startup();

    try std.testing.expectEqual(0, app.resource_store.clone(RemovedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(NotRemovedTicks));

    // remove component from entity
    try app.runOne();
    try std.testing.expectEqual(1, app.resource_store.clone(NotRemovedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(RemovedTicks));

    // deferred apply at the beginning of the run actually applies changes
    // removed logs is written now, which means it can be read in the next tick
    try app.runOne();
    try std.testing.expectEqual(2, app.resource_store.clone(NotRemovedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(RemovedTicks));

    // now the removed log can be read
    try app.runOne();
    try std.testing.expectEqual(2, app.resource_store.clone(NotRemovedTicks));
    try std.testing.expectEqual(1, app.resource_store.clone(RemovedTicks));
}
