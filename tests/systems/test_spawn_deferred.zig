const std = @import("std");
const eczinho = @import("eczinho");

test "spawn deferred without component" {
    const Context = eczinho.AppContextBuilder.init()
        .build();

    const Commands = Context.Commands;

    var app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Startup, (struct {
            pub fn spawnEntity(commands: Commands) void {
                _ = commands.spawn();
            }
        }).spawnEntity)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();

    try std.testing.expectEqual(0, app.world.len());

    try app.startup();

    try std.testing.expectEqual(1, app.world.len());
}
