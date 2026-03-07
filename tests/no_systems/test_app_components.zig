const eczinho = @import("eczinho");
const std = @import("std");

test "simple" {
    const typeA = struct { a: u34 };
    const Context = eczinho.AppContextBuilder.init()
        .addComponent(typeA)
        .build();
    var app = eczinho.AppBuilder
        .init(Context)
        .build(std.testing.allocator);
    defer app.deinit();
}
