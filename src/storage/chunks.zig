const std = @import("std");
const types = @import("../types.zig");

pub const ChunksOptions = struct {
    Entity: type,
    Components: type,
    InitialNumChunks: usize = 0,
    ChunkSize: usize = 1024 * 16, // 16 KB
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
        pub const ChunkSize = options.ChunkSize;
        pub const Chunk = ChunkFactory(options);
        pub const MaxAlignment = @max(Components.MaxAlignment, @alignOf(Entity), @alignOf(types.Tick));
        pub const MaxCapacity = @divFloor(ChunkSize, @sizeOf(Entity));
        pub const StorageAddress = struct { *Chunk, usize };
        pub const Storage = Chunk;

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

        pub fn init(signature: Components) !@This() {
            const dense_sig = signature.applyStorageTypeMask(.Dense);
            const capacity_per_chunk = calculateCapacity(dense_sig);
            const chunk_layout = ChunkLayout.init(dense_sig, capacity_per_chunk);
            return .{
                .capacity_per_chunk = capacity_per_chunk,
                .signature = dense_sig,
                .chunk_layout = chunk_layout,
            };
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
            pub inline fn indices(self: *const @This()) struct { usize, usize } {
                return .{ self.chunk_index, self.slot_index };
            }
            inline fn getChunk(self: *@This()) *Chunk {
                return self.chunks.chunks.items[self.chunk_index];
            }
            inline fn isWithinRange(self: *@This()) bool {
                return self.chunk_index < self.chunks.chunks.items.len and self.slot_index < self.getChunk().len();
            }
            pub inline fn peek(self: *@This()) ?struct { *Chunk, usize } {
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
            pub inline fn next(self: *@This()) ?struct { *Chunk, usize } {
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

pub fn ChunkFactory(comptime options: ChunksOptions) type {
    return struct {
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const CountInt = std.math.IntFittingRange(0, options.ChunkSize);
        pub const Chunks = ChunksFactory(options);
        chunks: *Chunks,
        count: CountInt,
        memory: [options.ChunkSize]u8 align(Chunks.MaxAlignment),
        pub fn init(chunks: *Chunks) @This() {
            return .{
                .chunks = chunks,
                .count = 0,
                // SAFETY: the whole point is that we manually manage this memory region
                .memory = undefined,
            };
        }
        inline fn getSignature(self: *@This()) Components {
            return self.chunks.signature;
        }
        inline fn getAddedMetadata(self: *@This(), comptime Component: type, index: usize) *types.Tick {
            if (comptime Component == Entity) {
                @compileError("Entity itself doesn't store metadata");
            }
            std.debug.assert(index < self.len());
            const arr_offset = self.chunks.chunk_layout.component_added_offsets.get(comptime Components.hash(Component)).?;
            const offset = arr_offset + @sizeOf(types.Tick) * index;
            return @alignCast(std.mem.bytesAsValue(types.Tick, self.memory[offset .. offset + @sizeOf(types.Tick)]));
        }
        inline fn getChangedArray(self: *@This(), comptime Component: type, index: usize) *types.Tick {
            if (comptime Component == Entity) {
                @compileError("Entity itself doesn't store metadata");
            }
            std.debug.assert(index < self.len());
            const arr_offset = self.chunks.chunk_layout.component_changed_offsets.get(comptime Components.hash(Component)).?;
            const offset = arr_offset + @sizeOf(types.Tick) * index;
            return @alignCast(std.mem.bytesAsValue(types.Tick, self.memory[offset .. offset + @sizeOf(types.Tick)]));
        }
        pub inline fn getAddedWithTypeId(self: *@This(), tid: Components.ComponentTypeId, index: usize) *types.Tick {
            std.debug.assert(index < self.len());
            const arr_offset = self.chunks.chunk_layout.component_added_offsets.get(tid).?;
            const offset = arr_offset + @sizeOf(types.Tick) * index;
            return @alignCast(std.mem.bytesAsValue(types.Tick, self.memory[offset .. offset + @sizeOf(types.Tick)]));
        }
        pub inline fn getChangedWithTypeId(self: *@This(), tid: Components.ComponentTypeId, index: usize) *types.Tick {
            std.debug.assert(index < self.len());
            const arr_offset = self.chunks.chunk_layout.component_added_offsets.get(tid).?;
            const offset = arr_offset + @sizeOf(types.Tick) * index;
            return @alignCast(std.mem.bytesAsValue(types.Tick, self.memory[offset .. offset + @sizeOf(types.Tick)]));
        }
        pub inline fn getComponentWithTypeId(self: *@This(), tid: Components.ComponentTypeId, index: usize) []u8 {
            std.debug.assert(index < self.len());
            const arr_offset = self.chunks.chunk_layout.component_data_offsets.get(tid).?;
            const tid_size = Components.getSize(tid);
            const offset = arr_offset + tid_size * index;
            return @alignCast(self.memory[offset .. offset + tid_size]);
        }
        pub inline fn empty(self: *const @This()) bool {
            return self.count == 0;
        }
        pub inline fn full(self: *const @This()) bool {
            return self.count == self.chunks.capacity_per_chunk;
        }
        pub fn reserve(self: *@This(), entt: Entity) usize {
            std.debug.assert(!self.full());
            self.count += 1;
            self.chunks.entity_count += 1;
            self.get(Entity, self.count - 1).* = entt;
            return self.count - 1;
        }
        pub fn get(self: *@This(), comptime Component: type, index: usize) *Component {
            std.debug.assert(index < self.len());
            const arr_offset = arr_offset: {
                if (comptime Component == Entity) break :arr_offset 0;
                break :arr_offset self.chunks.chunk_layout.component_data_offsets.get(comptime Components.hash(Component)).?;
            };
            const offset = arr_offset + @sizeOf(Component) * index;
            return @alignCast(std.mem.bytesAsValue(Component, self.memory[offset .. offset + @sizeOf(Component)]));
        }
        pub fn getConst(self: *@This(), comptime Component: type, index: usize) Component {
            std.debug.assert(index < self.len());
            return self.get(Component, index).*;
        }
        pub inline fn len(self: *@This()) usize {
            return self.count;
        }
        /// Return swapped entity and its new index
        pub fn remove(self: *@This(), allocator: std.mem.Allocator, index: usize) !?struct { usize, usize } {
            std.debug.assert(index < self.len());
            defer self.count -= 1;
            defer self.chunks.entity_count -= 1;

            if (index != self.count - 1 and comptime Components.Len != 0) {
                // swap remove entity ID
                self.get(Entity, index).* = self.getConst(Entity, self.count - 1);

                const signature = self.getSignature();
                const non_empty = signature.applyNonEmptyMask();
                var iter = non_empty.iterator();
                while (iter.nextTypeId()) |tid| {
                    // swap component data
                    @memcpy(self.getComponentWithTypeId(tid, index), self.getComponentWithTypeId(tid, self.count - 1));
                }
                const has_added_metadata = signature.applyAddedMask();
                iter = has_added_metadata.iterator();
                while (iter.nextTypeId()) |tid| {
                    self.getAddedWithTypeId(tid, index).* = self.getAddedWithTypeId(tid, self.count - 1).*;
                }
                const has_changed_metadata = signature.applyChangedMask();
                iter = has_changed_metadata.iterator();
                while (iter.nextTypeId()) |tid| {
                    self.getChangedWithTypeId(tid, index).* = self.getChangedWithTypeId(tid, self.count - 1).*;
                }
                const swapped_entt = self.getConst(Entity, index);
                return .{
                    swapped_entt.index,
                    index,
                };
            }

            if (self.empty()) {
                try self.chunks.free_list.append(allocator, self);
            }
            return null;
        }
    };
}

test ChunksFactory {
    const Entity = @import("../entity/entity.zig").EntityTypeFactory(.medium);
    const Components = @import("../components.zig").Components(&.{ u64, u32, bool, u16 });
    const signature: Components = Components.init(&.{ u64, bool });
    var chunks = try ChunksFactory(.{
        .Entity = Entity,
        .Components = Components,
    }).init(signature, std.testing.allocator);
    defer chunks.deinit();
}
