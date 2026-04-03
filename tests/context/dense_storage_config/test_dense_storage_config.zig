const std = @import("std");
const eczinho = @import("eczinho");

test "use dense chunked storage" {
    const ComponentA = struct { a: f32 };
    const Context = eczinho.AppContextBuilder.init()
        .setDenseStorageConfig(.{ .Chunks = .{
            .ChunkSize = 123,
            .InitialNumChunks = 321,
        } })
        .addComponent(ComponentA)
        .build();
    try std.testing.expectEqual(eczinho.DenseStorageConfig{
        .Chunks = .{
            .ChunkSize = 123,
            .InitialNumChunks = 321,
        },
    }, Context.DenseStorageConfig);
}

test "use dense tabled storage" {
    const ComponentA = struct { a: f32 };
    const Context = eczinho.AppContextBuilder.init()
        .setDenseStorageConfig(.{ .Tables = .{
            .InitialSize = 123,
        } })
        .addComponent(ComponentA)
        .build();
    try std.testing.expectEqual(eczinho.DenseStorageConfig{
        .Tables = .{
            .InitialSize = 123,
        },
    }, Context.DenseStorageConfig);
}
