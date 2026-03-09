const std = @import("std");
const eczinho = @import("eczinho");

test "add components in system" {
    const typeA = u64;
    const typeB = u32;
    const Context = eczinho.AppContextBuilder.init()
        .addComponents(&.{ typeA, typeB })
        .build();

    const Commands = Context.Commands;
    const Query = Context.Query;

    var app = eczinho.AppBuilder.init(Context)
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
        .build(std.testing.allocator);
    defer app.deinit();

    try std.testing.expectEqual(0, app.registry.len());

    try app.startup();

    // running schedule once won't change anything because
    // the syncing only happens at the beginning
    try app.runOne();
    try std.testing.expectEqual(0, app.registry.len());

    // syncs last run's changes and apply new deferred changes
    try app.runOne();
    try std.testing.expectEqual(1, app.registry.len());

    // uncommenting this would panic, since 'optSingle' would find more than one entity that
    // matches the query
    // try app.runOne();
    // try std.testing.expectEqual(2, app.registry.len());
}
