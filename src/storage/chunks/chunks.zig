const std = @import("std");
const types = @import("../../types.zig");
const ChunkFactory = @import("chunk.zig").ChunkFactory;

pub const ChunksConfig = struct {
    InitialNumChunks: usize = 0,
    ChunkSize: usize = 1024 * 16, // 16 KB
};

pub const ChunksOptions = struct {
    Entity: type,
    Components: type,
    Config: ChunksConfig,
};

/// Chunk layout:
/// +-------------------------------------------------------------------------+
/// | row of entity ids                                                       |
/// | row of non empty C1                                                     |
/// | row of data for non empty C2                                            |
/// |             ...                                                         |
/// | row of data for non empty CN                                            |
/// | ----------------------------------------------------------------------- /
/// | row of added ticks for first non empty component that has it enabled    |
/// | row of added ticks for second non empty component that has it enabled   |
/// | ...                                                                     |
/// | row of added ticks for last non empty component that has it enabled     |
/// | ----------------------------------------------------------------------- /
/// | row of changed ticks for first non empty component that has it enabled  |
/// | row of changed ticks for second non empty component that has it enabled |
/// | ...                                                                     |
/// | row of changed ticks for last non empty component that has it enabled   |
/// | ----------------------------------------------------------------------- /
/// | row of added ticks for first empty component that has it enabled        |
/// | row of added ticks for second empty component that has it enabled       |
/// | ...                                                                     |
/// | row of added ticks for last empty component that has it enabled         |
/// +-------------------------------------------------------------------------+
pub fn ChunksFactory(comptime options: ChunksOptions) type {
    return struct {
        const Chunks = @This();
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const ChunkSize = options.Config.ChunkSize;
        pub const Chunk = ChunkFactory(options);
        pub const MaxAlignment = @max(Components.MaxAlignment, @alignOf(Entity), @alignOf(types.Tick));
        pub const MaxCapacity = @divFloor(ChunkSize, @sizeOf(Entity));
        pub const StorageAddress = struct { *Chunk, usize };
        pub const Storage = Chunk;
        pub const RemovalResult = struct {
            usize,
            usize,
        };

        const ChunkLayout = struct {
            component_data_offsets: std.EnumMap(Components.ComponentTypeId, usize),
            component_added_offsets: std.EnumMap(Components.ComponentTypeId, usize),
            component_changed_offsets: std.EnumMap(Components.ComponentTypeId, usize),

            pub fn init(signature: Components, capacity: usize) @This() {
                var non_empty = signature.applyNonEmptyMask();
                var component_data_offsets = std.EnumMap(Components.ComponentTypeId, usize){};
                var component_added_offsets = std.EnumMap(Components.ComponentTypeId, usize){};
                var component_changed_offsets = std.EnumMap(Components.ComponentTypeId, usize){};

                if (comptime Components.Len != 0) {
                    var offset = @sizeOf(Entity) * capacity;
                    var iter = non_empty.iterator();
                    // non empty component data
                    while (iter.nextTypeId()) |tid| {
                        offset = std.mem.alignForward(usize, offset, Components.getAlignment(tid));
                        component_data_offsets.put(tid, offset);
                        offset += Components.getSize(tid) * capacity;
                    }
                    // non empty component added metadata
                    iter = non_empty.applyAddedMask().iterator();
                    offset = std.mem.alignForward(usize, offset, @alignOf(types.Tick));
                    while (iter.nextTypeId()) |tid| {
                        component_added_offsets.put(tid, offset);
                        offset += @sizeOf(types.Tick) * capacity;
                    }
                    // non empty component changed metadata
                    iter = non_empty.applyChangedMask().iterator();
                    offset = std.mem.alignForward(usize, offset, @alignOf(types.Tick));
                    while (iter.nextTypeId()) |tid| {
                        component_changed_offsets.put(tid, offset);
                        offset += @sizeOf(types.Tick) * capacity;
                    }
                    // empty component added metadata
                    iter = signature.applyEmptyMask().applyAddedMask().iterator();
                    offset = std.mem.alignForward(usize, offset, @alignOf(types.Tick));
                    while (iter.nextTypeId()) |tid| {
                        component_added_offsets.put(tid, offset);
                        offset += @sizeOf(types.Tick) * capacity;
                    }
                }
                return .{
                    .component_data_offsets = component_data_offsets,
                    .component_added_offsets = component_added_offsets,
                    .component_changed_offsets = component_changed_offsets,
                };
            }

            pub fn getComponentOffset(self: *const @This(), comptime Component: type) ?usize {
                return self.component_data_offsets.get(Components.hash(Component));
            }
            pub fn getComponentAddedOffset(self: *const @This(), comptime Component: type) ?usize {
                return self.component_added_offsets.get(Components.hash(Component));
            }
            pub fn getComponentChangedOffset(self: *const @This(), comptime Component: type) ?usize {
                return self.component_changed_offsets.get(Components.hash(Component));
            }
        };

        entity_count: usize = 0,

        chunks: std.ArrayList(*Chunk) = .empty,

        free_list: std.ArrayList(*Chunk) = .empty,

        insertion_chunk: ?*Chunk = null,

        signature: Components,

        capacity_per_chunk: usize,

        chunk_layout: ChunkLayout,

        pub fn init(allocator: std.mem.Allocator, signature: Components) !@This() {
            const dense_sig = signature.applyStorageTypeMask(.Dense);
            const capacity_per_chunk = calculateCapacity(dense_sig);
            const chunk_layout = ChunkLayout.init(dense_sig, capacity_per_chunk);
            var new = @This(){
                .capacity_per_chunk = capacity_per_chunk,
                .signature = dense_sig,
                .chunk_layout = chunk_layout,
            };
            if (comptime options.Config.InitialNumChunks != 0) {
                new.chunks.ensureTotalCapacity(allocator, options.Config.InitialNumChunks);
            }
            return new;
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.chunks.items) |chunk| {
                allocator.destroy(chunk);
            }
            self.free_list.deinit(allocator);
            self.chunks.deinit(allocator);
        }

        inline fn tableSize(signature: Components, n: usize) usize {
            const non_empty_sig = signature.applyNonEmptyMask();
            const zst_sig = signature.applyEmptyMask();
            // start with the entities
            var size = @sizeOf(Entity) * n;
            // count non empty components space
            var iter = non_empty_sig.iterator();
            while (iter.nextTypeId()) |tid| {
                size = std.mem.alignForward(usize, size, Components.getAlignment(tid));
                size += Components.getSize(tid) * n;
            }
            // count added metadata for non empty types that have it
            size = std.mem.alignForward(usize, size, @alignOf(types.Tick));
            size += @sizeOf(types.Tick) * n * non_empty_sig.applyAddedMask().len();

            // count changed metadata for non empty types that have it
            size = std.mem.alignForward(usize, size, @alignOf(types.Tick));
            size += @sizeOf(types.Tick) * n * non_empty_sig.applyChangedMask().len();

            // count added metadata for empty types that have it
            size += @sizeOf(types.Tick) * n * zst_sig.applyAddedMask().len();
            return size;
        }
        /// binary search for highest possible capacity
        inline fn calculateCapacity(signature: Components) usize {
            var upper: usize = MaxCapacity;
            var lower: usize = 1;
            while (lower < upper) {
                const mid = @divFloor(lower + upper + 1, 2);
                if (tableSize(signature, mid) <= ChunkSize) {
                    lower = mid;
                } else {
                    upper = mid - 1;
                }
            }
            return lower;
        }
        inline fn getInsertionChunk(self: *@This(), allocator: std.mem.Allocator) !*Chunk {
            if (self.insertion_chunk) |chunk| {
                if (!chunk.full()) {
                    return chunk;
                }
            }
            if (self.free_list.pop()) |free_chunk| {
                self.insertion_chunk = free_chunk;
                return free_chunk;
            }
            const chunk_ptr = try allocator.create(Chunk);
            chunk_ptr.* = Chunk.init(self);
            self.insertion_chunk = chunk_ptr;
            try self.chunks.append(allocator, chunk_ptr);
            return self.chunks.items[self.chunks.items.len - 1];
        }
        pub fn reserve(self: *@This(), allocator: std.mem.Allocator, entt: Entity) !StorageAddress {
            const chunk = try self.getInsertionChunk(allocator);
            const index = chunk.reserve(entt);
            return .{ chunk, index };
        }
        pub fn len(self: *const @This()) usize {
            return self.entity_count;
        }

        pub const Iterator = struct {
            chunk_index: usize = 0,
            slot_index: usize = 0,
            chunks: *Chunks,
            pub fn init(chunks: *Chunks) @This() {
                return .{
                    .chunks = chunks,
                };
            }
            inline fn getChunk(self: *@This()) *Chunk {
                return self.chunks.chunks.items[self.chunk_index];
            }
            inline fn isWithinRange(self: *@This()) bool {
                return self.chunk_index < self.chunks.chunks.items.len and self.slot_index < self.getChunk().len();
            }
            pub inline fn peek(self: *@This()) ?StorageAddress {
                const old_chunk_index = self.chunk_index;
                const old_slot_index = self.slot_index;
                const next_result = self.next();
                self.chunk_index = old_chunk_index;
                self.slot_index = old_slot_index;
                return next_result;
            }
            inline fn setNextValidChunk(self: *@This()) void {
                self.chunk_index += 1;
                while (self.chunk_index < self.chunks.chunks.items.len and self.getChunk().empty()) {
                    self.chunk_index += 1;
                }
            }
            inline fn optGetChunk(self: *@This()) ?*Chunk {
                if (self.chunk_index < self.chunks.chunks.items.len) {
                    return self.getChunk();
                }
                return null;
            }
            inline fn findNextValidChunk(self: *@This()) ?*Chunk {
                self.chunk_index += 1;
                while (self.optGetChunk() != null) : (self.chunk_index += 1) {
                    const chunk = self.getChunk();
                    if (chunk.len() != 0) {
                        return chunk;
                    }
                }
                return null;
            }
            pub inline fn next(self: *@This()) ?StorageAddress {
                if (self.chunk_index >= self.chunks.chunks.items.len) {
                    return null;
                }
                if (self.slot_index >= self.getChunk().len()) {
                    if (self.findNextValidChunk() == null) {
                        return null;
                    }
                }
                defer self.slot_index += 1;
                return .{ self.getChunk(), self.slot_index };
            }
        };
    };
}

test ChunksFactory {
    const Entity = @import("../../entity/entity.zig").EntityTypeFactory(.medium);
    const Components = @import("../../components.zig").Components(&.{ u64, u32, bool, u16 });
    const signature: Components = Components.init(&.{ u64, bool });
    var chunks = try ChunksFactory(.{
        .Entity = Entity,
        .Components = Components,
    }).init(signature, std.testing.allocator);
    defer chunks.deinit();
}
