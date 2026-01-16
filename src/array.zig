const std = @import("std");

pub const Array = struct {
    /// Original allocation returned by allocator (for freeing)
    backing: ?[]u8,

    /// Aligned region actually used for items
    data: []u8,

    item_size: usize,
    item_align: usize,

    /// how many items stored
    len: usize,
    /// how many items allocated for
    capacity: usize,

    pub fn init(item_size: usize, item_align: usize) Array {
        return .{
            .backing = null,
            .data = &[_]u8{},

            .item_size = item_size,
            .item_align = item_align,

            .len = 0,
            .capacity = 0,
        };
    }

    pub fn deinit(self: *Array, allocator: std.mem.Allocator) void {
        if (self.backing) |mem| {
            allocator.free(mem);
        }
    }

    fn getU8Index(self: *Array, index: usize) usize {
        return index * self.item_size;
    }

    pub fn length(self: *Array) usize {
        return self.len;
    }

    /// Called when memory growth is necessary. Returns a capacity larger than
    /// minimum that grows super-linearly.
    fn growCapacity(self: *@This(), minimum: usize) usize {
        const init_capacity = @max(1, (std.atomic.cache_line / self.item_size));
        var new = self.capacity;
        while (true) {
            new +|= new / 2 + init_capacity;
            if (new >= minimum)
                return new;
        }
    }

    fn ensureCapacity(
        self: *Array,
        allocator: std.mem.Allocator,
        minimum_new_capacity: usize,
    ) !void {
        if (minimum_new_capacity <= self.capacity)
            return;

        const new_capacity = self.growCapacity(minimum_new_capacity);
        const new_bytes = new_capacity * self.item_size;

        // Over-allocate to guarantee we can align manually
        // CANNOT realloc: we don't have guarantees on the base pointer alignment!
        // so the realloc memcpy might not match the current items!
        const raw = try allocator.alloc(
            u8,
            new_bytes + self.item_align,
        );

        // Align inside the allocation
        const aligned_ptr = std.mem.alignPointer(
            raw.ptr,
            self.item_align,
        ).?;

        const aligned = aligned_ptr[0..new_bytes];

        // Copy old data if it exists
        if (self.len > 0) {
            @memcpy(
                aligned[0 .. self.len * self.item_size],
                self.data[0 .. self.len * self.item_size],
            );
        }

        // Free old backing allocation
        if (self.backing) |old| {
            allocator.free(old);
        }

        self.backing = raw;
        self.data = aligned;
        self.capacity = new_capacity;
    }

    pub fn reserve(
        self: *Array,
        allocator: std.mem.Allocator,
        additional: usize,
    ) !void {
        try self.ensureCapacity(allocator, self.len + additional);
        self.len += 1;
    }

    pub fn append(
        self: *Array,
        allocator: std.mem.Allocator,
        value: anytype,
    ) !void {
        try self.reserve(allocator, 1);

        const dest = self.get(self.len - 1);
        @memcpy(dest, std.mem.asBytes(&value));
    }

    pub fn get(self: *Array, index: usize) []u8 {
        std.debug.assert(index < self.len);

        const start = self.getU8Index(index);
        return self.data[start .. start + self.item_size];
    }

    pub fn getAs(self: *Array, comptime T: type, index: usize) *T {
        return @alignCast(std.mem.bytesAsValue(T, self.get(index)));
    }

    pub fn getConst(self: *Array, comptime T: type, index: usize) T {
        return self.getAs(T, index).*;
    }

    pub fn removeLast(self: *Array) void {
        std.debug.assert(self.len > 0);
        self.len -= 1;
    }

    pub fn swapRemove(self: *Array, i: usize) void {
        std.debug.assert(i < self.len);

        if (i == self.len - 1) {
            self.removeLast();
            return;
        }

        @memcpy(self.get(i), self.get(self.len - 1));

        self.len -= 1;
    }
};
