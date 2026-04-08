const std = @import("std");
const eczinho = @import("eczinho");

test "jump dense tabled components into new archetype" {
    const typeA = u64;
    const typeB = u32;
    const typeC = u31;
    const typeD = u33;
    const Context = eczinho.AppContextBuilder.init()
        .addComponents(&.{ typeA, typeB, typeC, typeD })
        .setDenseStorageConfig(.{ .Tables = .{} })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, (struct {
            pub fn testSystemA(comms: Commands) !void {
                _ = comms.spawn()
                    .add(@as(u64, 1))
                    .add(@as(u32, 2))
                    .add(@as(u31, 3))
                    .add(@as(u33, 4));
            }
        }).testSystemA)
        .addSystem(.Update, (struct {
            pub fn testSystemB(q: Query(.{ .q = &.{ typeA, typeB, typeC, typeD } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32, const _u31, const _u33 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                    try std.testing.expectEqual(3, _u31);
                    try std.testing.expectEqual(4, _u33);
                }
            }
        }).testSystemB)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.world.len());

    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{typeA})));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB })));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC })));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC, typeD })));

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.world.len());

    try std.testing.expectEqual(0, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{})).?.len());
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{typeA})));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB })));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC })));
    try std.testing.expectEqual(1, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC, typeD })).?.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.world.len());
}

test "jump dense chunked components into new archetype" {
    const typeA = u64;
    const typeB = u32;
    const typeC = u31;
    const typeD = u33;
    const Context = eczinho.AppContextBuilder.init()
        .addComponents(&.{ typeA, typeB, typeC, typeD })
        .setDenseStorageConfig(.{ .Chunks = .{} })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, (struct {
            pub fn testSystemA(comms: Commands) !void {
                _ = comms.spawn()
                    .add(@as(u64, 1))
                    .add(@as(u32, 2))
                    .add(@as(u31, 3))
                    .add(@as(u33, 4));
            }
        }).testSystemA)
        .addSystem(.Update, (struct {
            pub fn testSystemB(q: Query(.{ .q = &.{ typeA, typeB, typeC, typeD } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32, const _u31, const _u33 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                    try std.testing.expectEqual(3, _u31);
                    try std.testing.expectEqual(4, _u33);
                }
            }
        }).testSystemB)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.world.len());

    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{typeA})));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB })));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC })));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC, typeD })));

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.world.len());

    try std.testing.expectEqual(0, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{})).?.len());
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{typeA})));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB })));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC })));
    try std.testing.expectEqual(1, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC, typeD })).?.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.world.len());
}

test "jump sparse components into new archetype" {
    const typeA = u64;
    const typeB = u32;
    const typeC = u31;
    const typeD = u33;
    const Context = eczinho.AppContextBuilder.init()
        .addComponentWithConfig(typeA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = false,
            },
        })
        .addComponentWithConfig(typeB, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = false,
            },
        })
        .addComponentWithConfig(typeC, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = false,
            },
        })
        .addComponentWithConfig(typeD, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = false,
            },
        })
        .setDenseStorageConfig(.{ .Chunks = .{} })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, (struct {
            pub fn testSystemA(comms: Commands) !void {
                _ = comms.spawn()
                    .add(@as(u64, 1))
                    .add(@as(u32, 2))
                    .add(@as(u31, 3))
                    .add(@as(u33, 4));
            }
        }).testSystemA)
        .addSystem(.Update, (struct {
            pub fn testSystemB(q: Query(.{ .q = &.{ typeA, typeB, typeC, typeD } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32, const _u31, const _u33 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                    try std.testing.expectEqual(3, _u31);
                    try std.testing.expectEqual(4, _u33);
                }
            }
        }).testSystemB)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.world.len());

    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{typeA})));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB })));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC })));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC, typeD })));

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.world.len());

    try std.testing.expectEqual(0, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{})).?.len());
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{typeA})));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB })));
    try std.testing.expectEqual(null, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC })));
    try std.testing.expectEqual(1, app
        .world.archetype_store.archetypes.get(Context.Components.init(&.{ typeA, typeB, typeC, typeD })).?.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.world.len());
}
