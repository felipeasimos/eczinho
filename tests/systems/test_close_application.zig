const std = @import("std");
const eczinho = @import("eczinho");

test "close application" {
    const Context = eczinho.AppContextBuilder.init()
        .build();

    const EventWriter = Context.EventWriter;

    var app = eczinho.AppBuilder.init(Context)
        .addSystem(.Update, (struct {
            pub fn spawnEntity(writer: EventWriter(eczinho.AppEvents.AppExit)) void {
                writer.write(eczinho.AppEvents.AppExit{});
            }
        }).spawnEntity)
        .build(std.testing.allocator);
    defer app.deinit();

    try app.startup();
    try app.runOne();

    try std.testing.expectEqual(1, app.event_store.total(eczinho.AppEvents.AppExit));
}
