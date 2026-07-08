const std = @import("std");
const eczinho = @import("eczinho");

test "DAG has two paralle. groups" {
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
            pub fn testSystemA(comms: Commands) !void {
                _ = comms.spawn().add(@as(u64, 1)).add(@as(u32, 2));
            }
        }).testSystemA)
        .addSystem(.Update, (struct {
            pub fn testSystemB(q: Query(.{ .q = &.{ typeA, typeB } })) !void {
                if (q.optSingle()) |tuple| {
                    const _u64, const _u32 = tuple;
                    try std.testing.expectEqual(1, _u64);
                    try std.testing.expectEqual(2, _u32);
                }
            }
        }).testSystemB)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    const DAG = @TypeOf(app).Scheduler.DAG(@TypeOf(app).Scheduler.Systems, Context.Components, Context.Resources, Context.Events, 4, &.{});
    try std.testing.expectEqual(1, DAG.ParallelGroups.len);
    try std.testing.expectEqual(2, DAG.ParallelGroups[0].Systems.len);
}

test "DAG has one parallel groups due to directional constraint" {
    const typeA = u64;
    const typeB = u32;
    const Context = eczinho.AppContextBuilder.init()
        .addComponents(&.{ typeA, typeB })
        .setDenseStorageConfig(.{ .Tables = .{} })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;
    const ConstraintBuilder = Context.ConstraintBuilder;

    const testSystemA = (struct {
        pub fn testSystemA(comms: Commands) !void {
            _ = comms.spawn().add(@as(u64, 1)).add(@as(u32, 2));
        }
    }).testSystemA;
    const testSystemB = (struct {
        pub fn testSystemB(q: Query(.{ .q = &.{ typeA, typeB } })) !void {
            if (q.optSingle()) |tuple| {
                const _u64, const _u32 = tuple;
                try std.testing.expectEqual(1, _u64);
                try std.testing.expectEqual(2, _u32);
            }
        }
    }).testSystemB;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, testSystemA)
        .addSystem(.Update, testSystemB)
        .addConstraint(ConstraintBuilder.after(.Update, testSystemA, testSystemB))
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    const DAG = @TypeOf(app).Scheduler.DAG(@TypeOf(app).Scheduler.Systems, Context.Components, Context.Resources, Context.Events, 4, @TypeOf(app).Scheduler.Constraints);
    try std.testing.expectEqual(2, DAG.ParallelGroups.len);
    try std.testing.expectEqual(1, DAG.ParallelGroups[0].Systems.len);
    try std.testing.expectEqual(1, DAG.ParallelGroups[1].Systems.len);
}
