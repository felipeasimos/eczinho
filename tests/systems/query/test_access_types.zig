const std = @import("std");
const eczinho = @import("eczinho");

test "add dense tabled components in system" {
    const typeA = u64;
    const typeB = u32;
    const Context = eczinho.AppContextBuilder.init()
        .addComponents(&.{ typeA, typeB })
        .setDenseStorageConfig(.{ .Tables = .{} })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, (struct {
            pub fn addComponents(comms: Commands) !void {
                _ = comms.spawn().add(@as(u64, 1)).add(@as(u32, 2));
            }
        }).addComponents)
        .addSystem(.Update, (struct {
            pub fn testConst(q: Query(.{ .q = &.{ typeA, typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                }
            }
        }).testConst)
        .addSystem(.Update, (struct {
            pub fn testPointerConst(q: Query(.{ .q = &.{ *const typeA, *const typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.*);
                    try std.testing.expectEqual(2, _u32.*);
                }
            }
        }).testPointerConst)
        .addSystem(.Update, (struct {
            pub fn testPointerMut(q: Query(.{ .q = &.{ *typeA, *typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.clone());
                    try std.testing.expectEqual(2, _u32.clone());
                }
            }
        }).testPointerMut)
        .addSystem(.Update, (struct {
            pub fn optionalConst(q: Query(.{ .q = &.{ ?typeA, ?typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64);
                        try std.testing.expectEqual(2, _u32);
                    }
                }
            }
        }).optionalConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerConst(
                q: Query(.{ .q = &.{ ?*const typeA, ?*const typeB } }),
                current_tick: eczinho.Tick,
            ) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.*);
                        try std.testing.expectEqual(2, _u32.?.*);
                    }
                }
            }
        }).optionalPointerConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerMut(q: Query(.{ .q = &.{ ?*typeA, ?*typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.clone());
                        try std.testing.expectEqual(2, _u32.?.clone());
                    }
                }
            }
        }).optionalPointerMut)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.world.len());

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.world.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.world.len());
}

test "add dense tabled components in system without metadata" {
    const typeA = u64;
    const typeB = u32;
    const Context = eczinho.AppContextBuilder.init()
        .addComponentWithConfig(typeB, .{
            .storage_type = .Dense,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = false,
            },
        })
        .addComponentWithConfig(typeA, .{
            .storage_type = .Dense,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = false,
            },
        })
        .setDenseStorageConfig(.{ .Tables = .{} })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, (struct {
            pub fn addComponents(comms: Commands) !void {
                _ = comms.spawn().add(@as(u64, 1)).add(@as(u32, 2));
            }
        }).addComponents)
        .addSystem(.Update, (struct {
            pub fn testConst(q: Query(.{ .q = &.{ typeA, typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                }
            }
        }).testConst)
        .addSystem(.Update, (struct {
            pub fn testPointerConst(q: Query(.{ .q = &.{ *const typeA, *const typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.*);
                    try std.testing.expectEqual(2, _u32.*);
                }
            }
        }).testPointerConst)
        .addSystem(.Update, (struct {
            pub fn testPointerMut(q: Query(.{ .q = &.{ *typeA, *typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.clone());
                    try std.testing.expectEqual(2, _u32.clone());
                }
            }
        }).testPointerMut)
        .addSystem(.Update, (struct {
            pub fn optionalConst(q: Query(.{ .q = &.{ ?typeA, ?typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64);
                        try std.testing.expectEqual(2, _u32);
                    }
                }
            }
        }).optionalConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerConst(
                q: Query(.{ .q = &.{ ?*const typeA, ?*const typeB } }),
                current_tick: eczinho.Tick,
            ) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.*);
                        try std.testing.expectEqual(2, _u32.?.*);
                    }
                }
            }
        }).optionalPointerConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerMut(q: Query(.{ .q = &.{ ?*typeA, ?*typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.clone());
                        try std.testing.expectEqual(2, _u32.?.clone());
                    }
                }
            }
        }).optionalPointerMut)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.world.len());

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.world.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.world.len());
}

test "add dense chunked components in system" {
    const typeA = u64;
    const typeB = u32;
    const Context = eczinho.AppContextBuilder.init()
        .addComponents(&.{ typeA, typeB })
        .setDenseStorageConfig(.{ .Chunks = .{} })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, (struct {
            pub fn addComponents(comms: Commands) !void {
                _ = comms.spawn().add(@as(u64, 1)).add(@as(u32, 2));
            }
        }).addComponents)
        .addSystem(.Update, (struct {
            pub fn testConst(q: Query(.{ .q = &.{ typeA, typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                }
            }
        }).testConst)
        .addSystem(.Update, (struct {
            pub fn testPointerConst(q: Query(.{ .q = &.{ *const typeA, *const typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.*);
                    try std.testing.expectEqual(2, _u32.*);
                }
            }
        }).testPointerConst)
        .addSystem(.Update, (struct {
            pub fn testPointerMut(q: Query(.{ .q = &.{ *typeA, *typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.clone());
                    try std.testing.expectEqual(2, _u32.clone());
                }
            }
        }).testPointerMut)
        .addSystem(.Update, (struct {
            pub fn optionalConst(q: Query(.{ .q = &.{ ?typeA, ?typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64);
                        try std.testing.expectEqual(2, _u32);
                    }
                }
            }
        }).optionalConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerConst(
                q: Query(.{ .q = &.{ ?*const typeA, ?*const typeB } }),
                current_tick: eczinho.Tick,
            ) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.*);
                        try std.testing.expectEqual(2, _u32.?.*);
                    }
                }
            }
        }).optionalPointerConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerMut(q: Query(.{ .q = &.{ ?*typeA, ?*typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.clone());
                        try std.testing.expectEqual(2, _u32.?.clone());
                    }
                }
            }
        }).optionalPointerMut)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.world.len());

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.world.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.world.len());
}

test "add dense chunked components in system without metadata" {
    const typeA = u64;
    const typeB = u32;
    const Context = eczinho.AppContextBuilder.init()
        .addComponentWithConfig(typeB, .{
            .storage_type = .Dense,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = false,
            },
        })
        .addComponentWithConfig(typeA, .{
            .storage_type = .Dense,
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
            pub fn addComponents(comms: Commands) !void {
                _ = comms.spawn().add(@as(u64, 1)).add(@as(u32, 2));
            }
        }).addComponents)
        .addSystem(.Update, (struct {
            pub fn testConst(q: Query(.{ .q = &.{ typeA, typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                }
            }
        }).testConst)
        .addSystem(.Update, (struct {
            pub fn testPointerConst(q: Query(.{ .q = &.{ *const typeA, *const typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.*);
                    try std.testing.expectEqual(2, _u32.*);
                }
            }
        }).testPointerConst)
        .addSystem(.Update, (struct {
            pub fn testPointerMut(q: Query(.{ .q = &.{ *typeA, *typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.clone());
                    try std.testing.expectEqual(2, _u32.clone());
                }
            }
        }).testPointerMut)
        .addSystem(.Update, (struct {
            pub fn optionalConst(q: Query(.{ .q = &.{ ?typeA, ?typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64);
                        try std.testing.expectEqual(2, _u32);
                    }
                }
            }
        }).optionalConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerConst(
                q: Query(.{ .q = &.{ ?*const typeA, ?*const typeB } }),
                current_tick: eczinho.Tick,
            ) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.*);
                        try std.testing.expectEqual(2, _u32.?.*);
                    }
                }
            }
        }).optionalPointerConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerMut(q: Query(.{ .q = &.{ ?*typeA, ?*typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.clone());
                        try std.testing.expectEqual(2, _u32.?.clone());
                    }
                }
            }
        }).optionalPointerMut)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.world.len());

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.world.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.world.len());
}

test "add sparse components in system without metadata" {
    const typeA = u64;
    const typeB = u32;
    const Context = eczinho.AppContextBuilder.init()
        .addComponentWithConfig(typeB, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = false,
            },
        })
        .addComponentWithConfig(typeA, .{
            .storage_type = .Sparse,
            .track_metadata = .{
                .added = false,
                .changed = false,
                .removed = false,
            },
        })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, (struct {
            pub fn addComponents(comms: Commands) !void {
                _ = comms.spawn().add(@as(u64, 1)).add(@as(u32, 2));
            }
        }).addComponents)
        .addSystem(.Update, (struct {
            pub fn testConst(q: Query(.{ .q = &.{ typeA, typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                }
            }
        }).testConst)
        .addSystem(.Update, (struct {
            pub fn testPointerConst(q: Query(.{ .q = &.{ *const typeA, *const typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.*);
                    try std.testing.expectEqual(2, _u32.*);
                }
            }
        }).testPointerConst)
        .addSystem(.Update, (struct {
            pub fn testPointerMut(q: Query(.{ .q = &.{ *typeA, *typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.clone());
                    try std.testing.expectEqual(2, _u32.clone());
                }
            }
        }).testPointerMut)
        .addSystem(.Update, (struct {
            pub fn optionalConst(q: Query(.{ .q = &.{ ?typeA, ?typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64);
                        try std.testing.expectEqual(2, _u32);
                    }
                }
            }
        }).optionalConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerConst(
                q: Query(.{ .q = &.{ ?*const typeA, ?*const typeB } }),
                current_tick: eczinho.Tick,
            ) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.*);
                        try std.testing.expectEqual(2, _u32.?.*);
                    }
                }
            }
        }).optionalPointerConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerMut(q: Query(.{ .q = &.{ ?*typeA, ?*typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.clone());
                        try std.testing.expectEqual(2, _u32.?.clone());
                    }
                }
            }
        }).optionalPointerMut)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.world.len());

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.world.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.world.len());
}

test "add dense chunked components in system with metadata" {
    const typeA = u64;
    const typeB = u32;
    const Context = eczinho.AppContextBuilder.init()
        .addComponentWithConfig(typeB, .{
            .storage_type = .Dense,
            .track_metadata = .{
                .added = true,
                .changed = true,
                .removed = true,
            },
        })
        .addComponentWithConfig(typeA, .{
            .storage_type = .Dense,
            .track_metadata = .{
                .added = true,
                .changed = true,
                .removed = true,
            },
        })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, (struct {
            pub fn addComponents(comms: Commands) !void {
                _ = comms.spawn().add(@as(u64, 1)).add(@as(u32, 2));
            }
        }).addComponents)
        .addSystem(.Update, (struct {
            pub fn testConst(q: Query(.{ .q = &.{ typeA, typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                }
            }
        }).testConst)
        .addSystem(.Update, (struct {
            pub fn testPointerConst(q: Query(.{ .q = &.{ *const typeA, *const typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.*);
                    try std.testing.expectEqual(2, _u32.*);
                }
            }
        }).testPointerConst)
        .addSystem(.Update, (struct {
            pub fn testPointerMut(q: Query(.{ .q = &.{ *typeA, *typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64.clone());
                    try std.testing.expectEqual(2, _u32.clone());
                }
            }
        }).testPointerMut)
        .addSystem(.Update, (struct {
            pub fn optionalConst(q: Query(.{ .q = &.{ ?typeA, ?typeB } }), current_tick: eczinho.Tick) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64);
                        try std.testing.expectEqual(2, _u32);
                    }
                }
            }
        }).optionalConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerConst(
                q: Query(.{ .q = &.{ ?*const typeA, ?*const typeB } }),
                current_tick: eczinho.Tick,
            ) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.*);
                        try std.testing.expectEqual(2, _u32.?.*);
                    }
                }
            }
        }).optionalPointerConst)
        .addSystem(.Update, (struct {
            pub fn optionalPointerMut(
                q: Query(.{ .q = &.{ ?*typeA, ?*typeB } }),
                current_tick: eczinho.Tick,
            ) !void {
                if (current_tick.eql(3)) {
                    if (q.optSingle()) |tuple| {
                        const _u64, const _u32 = tuple;
                        try std.testing.expectEqual(1, _u64.?.clone());
                        try std.testing.expectEqual(2, _u32.?.clone());
                    }
                }
            }
        }).optionalPointerMut)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.world.len());

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.world.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.world.len());
}
