const std = @import("std");
const eczinho = @import("eczinho");

test "check if component was just changed" {
    const ComponentA = u64;
    const ComponentB = u32;
    const ChangedTicks = u32;
    const NotChangedTicks = u31;
    const Context = eczinho.AppContextBuilder.init()
        .addComponent(ComponentA)
        .addComponent(ComponentB)
        .addResource(ChangedTicks)
        .addResource(NotChangedTicks)
        .build();

    const Resource = Context.Resource;
    const ResourceStore = Context.ResourceStore;
    const Commands = Context.Commands;
    const Query = Context.Query;
    const Entity = Context.Entity;

    var app = eczinho.AppBuilder.init(Context)
        .addSystem(.Startup, (struct {
            pub fn addResource(store: *ResourceStore) !void {
                store.insert(@as(ChangedTicks, 0));
                store.insert(@as(NotChangedTicks, 0));
            }
        }).addResource)
        .addSystem(.Startup, (struct {
            pub fn spawnEntity(comms: Commands) void {
                _ = comms.spawn().add(@as(ComponentA, 5)).add(@as(ComponentB, 6));
            }
        }).spawnEntity)
        .addSystem(.Update, (struct {
            pub fn checkIfNotChanged(res: Resource(NotChangedTicks), q: Query(.{ .q = &.{ComponentA}, .changed = &.{ComponentB} })) void {
                if (q.len() == 0) {
                    res.get().* += 1;
                }
            }
        }).checkIfNotChanged)
        .addSystem(.Update, (struct {
            pub fn checkIfChanged(res: Resource(ChangedTicks), q: Query(.{ .q = &.{ComponentA}, .changed = &.{ComponentB} })) void {
                if (q.len() > 0) {
                    res.get().* += 1;
                }
            }
        }).checkIfChanged)
        .addSystem(.Update, (struct {
            pub fn changeIfNotChanged(q_write: Query(.{ .q = &.{*ComponentB}, .with = &.{ComponentA} }), q_read: Query(.{ .q = &.{Entity}, .with = &.{ ComponentB, ComponentA }, .changed = &.{ComponentB} })) void {
                if (q_read.peek() == null) {
                    const comp_b = q_write.single();
                    _ = comp_b;
                }
            }
        }).changeIfNotChanged)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    // spawn entity without component
    try app.startup();

    // adding the component count as a "change"
    // however it is not applied yet
    try std.testing.expectEqual(0, app.resource_store.clone(ChangedTicks));
    try std.testing.expectEqual(0, app.resource_store.clone(NotChangedTicks));

    // startup change is applied
    // also, update change is not queued (since there is already a changed component)
    try app.runOne();
    try std.testing.expectEqual(0, app.resource_store.clone(NotChangedTicks));
    try std.testing.expectEqual(1, app.resource_store.clone(ChangedTicks));

    // changed status is gone, a new change is queued
    try app.runOne();
    try std.testing.expectEqual(1, app.resource_store.clone(NotChangedTicks));
    try std.testing.expectEqual(1, app.resource_store.clone(ChangedTicks));

    // update change is applied
    try app.runOne();
    try std.testing.expectEqual(1, app.resource_store.clone(NotChangedTicks));
    try std.testing.expectEqual(2, app.resource_store.clone(ChangedTicks));
}
