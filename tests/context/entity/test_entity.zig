const eczinho = @import("eczinho");
const std = @import("std");

test "set index and version bits for entity" {
    const Context = eczinho.AppContextBuilder.init()
        .setEntityConfig(.{ .index_bits = 11, .version_bits = 5 })
        .build();
    try std.testing.expectEqual(u11, Context.Entity.Index);
    try std.testing.expectEqual(u5, Context.Entity.Version);
    try std.testing.expectEqual(u16, Context.Entity.Int);
}
