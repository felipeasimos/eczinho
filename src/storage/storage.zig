pub const chunks = @import("chunks.zig");
pub const sparseset = @import("sparseset.zig");

pub const StorageConfig = union {
    chunks: chunks.ChunkOptions,
    sparseset: sparseset.SparseSetOptions,
};

pub const StorageOptions = struct {
    Entity: type,
    Components: type,
    Config: StorageConfig,
};

pub fn Storage(options: StorageOptions) type {
    return switch (options.Config) {
        .chunks => |c| chunks.ChunksFactory(c),
        .sparseset => |s| sparseset.SparseSet(s),
    };
}
