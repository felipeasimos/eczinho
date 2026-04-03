pub const chunks = @import("chunks/chunks.zig");
pub const tables = @import("tables/tables.zig");
pub const sparsesets = @import("sparseset/sparsesets.zig");
const DenseStorageType = @import("storage_types.zig").DenseStorageType;

pub const DenseStorageConfig = union(DenseStorageType) {
    Chunks: chunks.ChunksConfig,
    Tables: tables.TablesConfig,
};

pub const DenseStorageOptions = struct {
    World: type,
    Config: DenseStorageConfig,
};

pub fn DenseStorage(options: DenseStorageOptions) type {
    return switch (options.Config) {
        .Chunks => |c| chunks.ChunksFactory(.{
            .Entity = options.World.Entity,
            .Components = options.World.Components,
            .Config = c,
        }),
        .Tables => |t| tables.TablesFactory(.{
            .Entity = options.World.Entity,
            .Components = options.World.Components,
            .Config = t,
        }),
    };
}

pub fn DenseStorageUnit(options: DenseStorageOptions) type {
    return switch (options.Config) {
        .Chunks => |c| chunks.ChunksFactory(c).Chunk,
        .Tables => |t| tables.TablesFactory(t),
    };
}
