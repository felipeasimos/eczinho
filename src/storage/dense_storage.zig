pub const chunks = @import("chunks.zig");
pub const tables = @import("table/tables.zig");
pub const sparsesets = @import("sparseset/sparsesets.zig");
const DenseStorageType = @import("storage_types.zig").DenseStorageType;

pub const DenseStorageConfig = union(DenseStorageType) {
    Chunks: chunks.ChunksOptions,
    Tables: tables.TablesOptions,
};

pub const DenseStorageOptions = struct {
    World: type,
    Config: DenseStorageConfig,
};

pub fn DenseStorage(options: DenseStorageOptions) type {
    return switch (options.Config) {
        .Chunks => |c| chunks.ChunksFactory(c),
        .Tables => |t| tables.Tables(t),
    };
}

pub fn DenseStorageUnit(options: DenseStorageOptions) type {
    return switch (options.Config) {
        .Chunks => |c| chunks.ChunksFactory(c).Chunk,
        .Tables => |t| tables.Tables(t),
    };
}
