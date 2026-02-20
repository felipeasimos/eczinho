const std = @import("std");
const Tick = @import("types.zig").Tick;

/// per-system persistent data, store in the scheduler struct.
/// Notice this isn't a custom created type. This is necessary to get proper pointers
/// in user-facing types that don't have system type information
pub const SystemData = struct {
    event_reader_next_indices: []usize,
    removed_log_reader_next_indices: []usize,
    last_run: Tick = 0,
    pub fn init(alloc: std.mem.Allocator, num_event_readers: usize, num_removed_readers: usize) !@This() {
        const event_next_indices_ptr = try alloc.alloc(usize, num_event_readers);
        @memset(event_next_indices_ptr, 0);
        const removed_next_indices_ptr = try alloc.alloc(usize, num_removed_readers);
        @memset(removed_next_indices_ptr, 0);
        return .{
            .event_reader_next_indices = event_next_indices_ptr,
            .removed_log_reader_next_indices = removed_next_indices_ptr,
        };
    }
    pub fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.event_reader_next_indices);
        alloc.free(self.removed_log_reader_next_indices);
    }
    pub fn getEventReaderIndexPtr(self: *@This(), reader_index: usize) *usize {
        return &self.event_reader_next_indices[reader_index];
    }
    pub fn getRemovedReaderIndexPtr(self: *@This(), reader_index: usize) *usize {
        return &self.removed_log_reader_next_indices[reader_index];
    }
};
