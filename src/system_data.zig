const std = @import("std");

/// per-system persistent data, store in the scheduler struct.
/// Notice this isn't a custom created type. This is necessary to get proper pointers
/// in user-facing types that don't have system type information
pub const SystemData = struct {
    event_reader_next_indices: []usize,
    pub fn init(alloc: std.mem.Allocator, num_event_readers: usize) !@This() {
        const next_indices_ptr = try alloc.alloc(usize, num_event_readers);
        @memset(next_indices_ptr, 0);
        return .{
            .event_reader_next_indices = next_indices_ptr,
        };
    }
    pub fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.event_reader_next_indices);
    }
    pub fn getNextEventIndex(self: *@This(), reader_index: usize) usize {
        const index_ptr = &self.event_reader_next_indices[reader_index];
        const index = index_ptr.*;
        index_ptr.* += 1;
        return index;
    }
    pub fn peekNextEventIndex(self: *@This(), reader_index: usize) usize {
        return self.event_reader_next_indices[reader_index];
    }
};
