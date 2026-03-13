const eczinho = @import("eczinho");
const std = @import("std");

test "simple" {
    const Context = eczinho.AppContextBuilder.init()
        .build();
    var app = eczinho.AppBuilder
        .init(Context)
        .build(std.testing.allocator, std.testing.io);
    defer app.deinit();
}
