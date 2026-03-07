const eczinho = @import("eczinho");
const std = @import("std");

test "resource insertion" {
    const ResourceA = struct { a: f32 };
    const Context = eczinho.AppContextBuilder.init()
        .addResource(ResourceA)
        .build();
    var app = eczinho.AppBuilder
        .init(Context)
        .build(std.testing.allocator);
    try app.insert(ResourceA{ .a = 34 });
    defer app.deinit();

    try std.testing.expect(app.resource_store.optGet(ResourceA) != null);
}
