const std = @import("std");
const types = @import("types.zig");

pub const ChunkOptions = struct {
    Entity: type,
    Components: type,
    ChunkSize: usize = 1024 * 16, // 16 KB
};

pub fn ChunksFactory(comptime options: ChunkOptions) type {
    return struct {
        const Chunks = @This();
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const ChunkSize = options.ChunkSize;
        pub const Chunk = ChunkFactory(options);
        pub const MaxAlignment = @max(Components.MaxAlignment, @alignOf(Entity));
        pub const MaxCapacity = @divFloor(ChunkSize, @sizeOf(Entity));

        allocator: std.mem.Allocator,

        entity_count: usize = 0,

        chunks: std.ArrayList(*Chunk) = .empty,

        free_list: std.ArrayList(*Chunk) = .empty,

        insertion_chunk: ?*Chunk = null,

        component_arrays_offsets: []usize,

        component_sizes: []usize,

        signature: Components,

        capacity_per_chunk: usize,

        tid_map_to_type_index: std.EnumMap(Components.ComponentTypeId, usize),

        pub fn init(signature: Components, alloc: std.mem.Allocator) !@This() {
            var sig = signature;
            var map = std.EnumMap(Components.ComponentTypeId, usize).initFull(Components.Len);
            var iter = signature.iterator();
            var i: usize = 0;
            while (iter.nextTypeIdNonEmpty()) |tid| {
                map.put(tid, i);
                i += 1;
            }
            const capacity_per_chunk = calculateCapacity(&sig);
            return .{
                .capacity_per_chunk = capacity_per_chunk,
                .component_arrays_offsets = try calculateOffsets(&sig, capacity_per_chunk, alloc),
                .component_sizes = try getSizes(&sig, alloc),
                .signature = signature,
                .allocator = alloc,
                .tid_map_to_type_index = map,
            };
        }
        pub fn deinit(self: *@This()) void {
            for (self.chunks.items) |chunk| {
                self.allocator.destroy(chunk);
            }
            self.chunks.deinit(self.allocator);
            self.allocator.free(self.component_arrays_offsets);
            self.allocator.free(self.component_sizes);
        }
        pub inline fn getSize(self: *const @This(), tid_or_component: anytype) ?usize {
            const type_index = self.getNonEmptyTypeIndex(tid_or_component);
            return self.component_sizes[type_index];
        }
        inline fn getSizes(signature: *Components, alloc: std.mem.Allocator) ![]usize {
            const sizes = try alloc.alloc(usize, signature.len());
            var iter = signature.iterator();
            var i: usize = 0;
            while (iter.nextTypeIdNonEmpty()) |tid| {
                sizes[i] = Components.getSize(tid);
                i += 1;
            }
            return sizes;
        }
        inline fn calculateOffsets(signature: *Components, capacity: usize, alloc: std.mem.Allocator) ![]usize {
            const offsets = try alloc.alloc(usize, signature.len() + 1);
            var iter = signature.iterator();
            var offset = capacity * @sizeOf(Entity);
            var i: usize = 0;
            while (iter.nextTypeIdNonEmpty()) |tid| {
                offset = std.mem.alignForward(usize, offset, Components.getAlignment(tid));
                offsets[i] = offset;
                offset += Components.getSize(tid) * capacity;
                i += 1;
            }
            // added and changed metadata start
            offsets[i] = std.mem.alignForward(usize, offset, @alignOf(types.Tick));
            return offsets;
        }
        inline fn tableSize(signature: *Components, n: usize) usize {
            var iter = signature.iterator();
            var size = @sizeOf(Entity) * n;
            var i: usize = 0;
            while (iter.nextTypeIdNonEmpty()) |tid| {
                size = std.mem.alignForward(usize, size, Components.getAlignment(tid));
                size += Components.getSize(tid) * n;
                i += 1;
            }
            // added and changed metadata
            size = std.mem.alignForward(usize, size, @alignOf(types.Tick));
            size += @sizeOf(types.Tick) * n * 2 * i;
            return size;
        }
        /// binary search for highest possible capacity
        inline fn calculateCapacity(signature: *Components) usize {
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
        pub inline fn getNonEmptyTypeIndex(self: *const @This(), tid_or_component: anytype) ?usize {
            const hash: Components.ComponentTypeId = if (comptime @TypeOf(tid_or_component) == type) Components.hash(tid_or_component) else tid_or_component;
            return self.tid_map_to_type_index.get(hash);
        }
        inline fn getInsertionChunk(self: *@This()) !*Chunk {
            if (self.insertion_chunk) |chunk| {
                if (!chunk.full()) {
                    return chunk;
                }
            }
            if (self.free_list.pop()) |free_chunk| {
                self.insertion_chunk = free_chunk;
                return free_chunk;
            }
            const chunk_ptr = try self.allocator.create(Chunk);
            chunk_ptr.* = Chunk.init(self);
            try self.chunks.append(self.allocator, chunk_ptr);
            return self.chunks.items[self.chunks.items.len - 1];
        }
        pub fn reserve(self: *@This(), entt: Entity) !struct { *Chunk, usize } {
            const chunk = try self.getInsertionChunk();
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
            pub inline fn next(self: *@This()) ?struct { *Chunk, usize } {
                if (!self.isWithinRange()) {
                    return null;
                }
                const chunk = self.getChunk();
                const result = .{ chunk, self.slot_index };
                if (self.getChunk().len() == self.slot_index + 1) {
                    self.setNextValidChunk();
                    self.slot_index = 0;
                }
                return result;
            }
        };
    };
}

pub fn ChunkFactory(comptime options: ChunkOptions) type {
    return struct {
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const CountInt = std.math.IntFittingRange(0, options.ChunkSize);
        pub const Chunks = ChunksFactory(options);
        memory: [options.ChunkSize]u8 align(Chunks.MaxAlignment),
        chunks: *Chunks,
        count: CountInt,
        pub fn init(chunks: *Chunks) @This() {
            return .{
                .chunks = chunks,
                .count = 0,
                // SAFETY: the whole point is that we manually manage this memory region
                .memory = undefined,
            };
        }
        inline fn getSignature(self: *@This()) *Components {
            return &self.chunks.signature;
        }
        inline fn getEntity(self: *@This(), slot_index: usize) *Entity {
            const start = @sizeOf(Entity) * slot_index;
            const end = start + @sizeOf(Entity);
            return @alignCast(std.mem.bytesAsValue(Entity, self.memory[start..end]));
        }
        inline fn getOffset(self: *const @This(), type_index: usize) usize {
            return self.chunks.component_arrays_offsets[type_index + 1]; // + 1 because of entity id
        }
        inline fn getSize(self: *const @This(), type_index: usize) usize {
            return self.chunks.component_sizes[type_index];
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
            return @intCast(self.count - 1);
        }
        pub fn getElemWithTypeIndex(self: *@This(), type_index: usize, elem_index: usize) []u8 {
            const size = self.getSize(type_index);
            const start = self.getOffset(type_index) + elem_index * size;
            const end = start + size;
            return self.memory[start..end];
        }
        pub fn getTypeIndex(self: *const @This(), tid_or_component: anytype) usize {
            return self.chunks.getNonEmptyTypeIndex(tid_or_component).?;
        }
        inline fn getElemWithType(self: *@This(), comptime Component: type, elem_index: usize) *Component {
            const start = self.getOffset(self.getTypeIndex(Component)) + elem_index * @sizeOf(Component);
            const end = start + @sizeOf(Component);
            return @alignCast(std.mem.bytesAsValue(Component, self.memory[start..end]));
        }
        pub fn get(self: *@This(), comptime Component: type, index: usize) *Component {
            std.debug.assert(index < self.len());
            if (comptime Component == Entity) {
                return self.getEntity(index);
            }
            return self.getElemWithType(Component, index);
        }
        pub fn getConst(self: *@This(), comptime Component: type, index: usize) Component {
            std.debug.assert(index < self.len());
            if (comptime Component == Entity) {
                return self.getEntity(index).*;
            }
            return self.get(Component, index).*;
        }
        pub inline fn len(self: *@This()) usize {
            return self.count;
        }
        const ComponentMetadata = enum {
            Added,
            Changed,
        };
        pub fn getMetadataArray(self: *@This(), type_index: usize, comptime metadata_type: ComponentMetadata) []types.Tick {
            const metadata_start = self.chunks.component_arrays_offsets[self.chunks.component_arrays_offsets.len - 1];
            const capacity = self.chunks.capacity_per_chunk;
            switch (metadata_type) {
                .Added => {
                    const start = metadata_start + type_index * @sizeOf(types.Tick) * capacity;
                    const end = start + @sizeOf(types.Tick) * capacity;
                    return @alignCast(std.mem.bytesAsSlice(types.Tick, self.memory[start..end]));
                },
                .Changed => {
                    const start = metadata_start + (self.getSignature().len() + type_index) * @sizeOf(types.Tick) * capacity;
                    const end = start + @sizeOf(types.Tick) * capacity;
                    return @alignCast(std.mem.bytesAsSlice(types.Tick, self.memory[start..end]));
                },
            }
        }
        /// Return swapped entity and its new index
        pub fn remove(self: *@This(), index: usize) struct { Entity, usize } {
            std.debug.assert(index < self.len());

            // swap remove entity ID
            self.get(Entity, index).* = self.getConst(Entity, self.count - 1);

            var iter = self.getSignature().iterator();

            var i: usize = 0;
            if (index != self.count - 1) {
                while (iter.nextTypeIdNonEmpty()) |_| {
                    // swap component data
                    @memcpy(self.getElemWithTypeIndex(i, index), self.getElemWithTypeIndex(i, self.count - 1));
                    const changed = self.getMetadataArray(i, .Changed);
                    changed[index] = changed[self.count - 1];
                    const added = self.getMetadataArray(i, .Added);
                    added[index] = added[self.count - 1];
                    i += 1;
                }
            }
            const swapped_entt = self.getConst(Entity, index);
            self.count -= 1;
            self.chunks.entity_count -= 1;
            return .{
                swapped_entt,
                index,
            };
        }
    };
}

test ChunksFactory {
    const Entity = @import("entity.zig").EntityTypeFactory(.medium);
    const Components = @import("components.zig").Components(&.{ u64, u32, bool, u16 });
    const signature: Components = Components.init(&.{ u64, bool });
    var chunks = try ChunksFactory(.{ .Entity = Entity, .Components = Components }).init(signature, std.testing.allocator);
    defer chunks.deinit();
}
