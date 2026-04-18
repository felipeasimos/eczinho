const std = @import("std");
const types = @import("../../types.zig");
const ChunksFactory = @import("chunks.zig").ChunksFactory;
const ChunksOptions = @import("chunks.zig").ChunksOptions;

pub fn ChunkFactory(comptime options: ChunksOptions) type {
    return struct {
        pub const Components = options.Components;
        pub const Entity = options.Entity;
        pub const CountInt = std.math.IntFittingRange(0, options.Config.ChunkSize);
        pub const Chunks = ChunksFactory(options);
        pub const StorageAddress = Chunks.StorageAddress;
        chunks: *Chunks,
        count: CountInt,
        memory: [options.Config.ChunkSize]u8 align(Chunks.MaxAlignment),
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
        pub inline fn getAddedArray(self: *@This(), tid_or_component: anytype) []types.Tick {
            const tid = if (comptime @TypeOf(tid_or_component) == type)
                comptime Components.hash(tid_or_component)
            else
                tid_or_component;
            const offset = self.chunks.chunk_layout.component_added_offsets.get(tid).?;
            const slice = self.memory[offset .. offset + @sizeOf(types.Tick) * self.count];
            return @alignCast(std.mem.bytesAsSlice(types.Tick, slice));
        }
        pub inline fn getAdded(self: *@This(), tid_or_component: anytype, index: usize) *types.Tick {
            return &self.getAddedArray(tid_or_component)[index];
        }
        pub inline fn getChangedArray(self: *@This(), tid_or_component: anytype) []types.Tick {
            const tid = if (comptime @TypeOf(tid_or_component) == type)
                comptime Components.hash(tid_or_component)
            else
                tid_or_component;
            const offset = self.chunks.chunk_layout.component_changed_offsets.get(tid).?;
            const slice = self.memory[offset .. offset + @sizeOf(types.Tick) * self.count];
            return @alignCast(std.mem.bytesAsSlice(types.Tick, slice));
        }
        pub inline fn getChanged(self: *@This(), tid_or_component: anytype, index: usize) *types.Tick {
            return &self.getChangedArray(tid_or_component)[index];
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
        pub inline fn contains(self: *@This(), comptime Component: type, entt: Entity, index: usize) bool {
            if (index < self.count and self.chunks.signature.has(Component)) {
                return self.get(Entity, index).* == entt;
            }
            return false;
        }
        pub fn getConst(self: *@This(), comptime Component: type, index: usize) Component {
            std.debug.assert(index < self.len());
            return self.get(Component, index).*;
        }
        pub inline fn len(self: *@This()) usize {
            return self.count;
        }
        /// Return swapped entity and its new index
        pub fn remove(self: *@This(), allocator: std.mem.Allocator, index: usize) !?Chunks.RemovalResult {
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
                    self.getAddedArray(tid)[index] = self.getAddedArray(tid)[self.count - 1];
                }
                const has_changed_metadata = signature.applyChangedMask();
                iter = has_changed_metadata.iterator();
                while (iter.nextTypeId()) |tid| {
                    self.getChangedArray(tid)[index] = self.getChangedArray(tid)[self.count - 1];
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
