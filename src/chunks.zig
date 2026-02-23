const std = @import("std");

pub const ChunkOptions = struct {
    Entity: type,
    Components: type,
    ChunkSize: usize = 1024 * 16, // 16 KB
};

pub fn ChunksFactory(comptime options: ChunkOptions) type {
    return struct {
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const Chunk = ChunkFactory(options);
        signature: *Components,
        entity_count: usize,
        chunks: std.ArrayList(*Chunk),
        allocator: std.mem.Allocator,
        pub fn init(signature: *Components, alloc: std.mem.Allocator) @This() {
            return .{
                .signature = signature,
                .entity_count = 0,
                .chunks = .empty,
                .allocator = alloc,
            };
        }
        pub fn deinit(self: *const @This()) void {
            for (self.chunks) |chunk| {
                self.allocator.destroy(chunk);
            }
            self.chunks.deinit(self.allocator);
        }
        // pub fn valid(self: *@This(), entt: Entity) bool {}
        // pub fn reserve(self: *@This(), entt: Entity) void {}
        // pub fn get(self: *@This(), comptime Component: type, entt: Entity) *Component {}
        // pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {}
        // pub fn remove(self: *@This(), entt: Entity) void {}
        // pub fn len(self: *const @This()) usize {
        //     return self.entity_count;
        // }
    };
}

pub fn ChunkFactory(comptime options: ChunkOptions) type {
    return struct {
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        memory: [options.ChunkSize]u8,
        count: std.math.IntFittingRange(0, options.ChunkSize),
        signature_ptr: *Components,
        pub fn init(signature_ptr: *Components) @This() {
            return .{
                .signature_ptr = signature_ptr,
                .count = 0,
                // SAFETY: the whole point is that we manually manage this memory region
                .memory = undefined,
            };
        }
        // pub fn valid(self: *@This(), entt: Entity) bool {}
        // pub fn reserve(self: *@This(), entt: Entity) void {}
        // pub fn get(self: *@This(), comptime Component: type, entt: Entity) *Component {}
        // pub fn getConst(self: *@This(), comptime Component: type, entt: Entity) Component {}
        // pub fn remove(self: *@This(), entt: Entity) void {}
    };
}
