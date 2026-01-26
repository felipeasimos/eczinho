const std = @import("std");

/// per-system persistent data, store in the scheduler struct.
/// Notice this isn't a custom created type. This is necessary to get proper pointers
/// in user-facing types that don't have system type information
pub const SystemData = struct {
    event_reader_next_indices: []usize,
    last_run: usize = 0,
    pub fn init(alloc: std.mem.Allocator, num_event_readers: usize) !@This() {
        return .{
            .event_reader_next_indices = try alloc.alloc(usize, num_event_readers),
        };
    }
    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        try alloc.free(self.event_reader_next_indices);
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
    pub fn updateIndexForBufferSwap(self: *@This(), reader_index: usize, previous_size: usize) void {
        const index_ptr = self.event_reader_next_indices[reader_index];
        // saturing subtraction: the result will be zero if
        // previous_size is greater than index_ptr.*
        index_ptr.* = index_ptr.* -| previous_size;
    }
};
