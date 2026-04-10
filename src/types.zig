pub const Tick = packed struct(u32) {
    tick: u32,
    pub const zero: @This() = .{ .tick = 0 };
    pub inline fn increment(self: *@This()) void {
        self.tick +%= 1;
    }
    pub inline fn eql(self: @This(), x: anytype) bool {
        return self.tick == x;
    }
    pub inline fn lessThan(self: @This(), other: @This()) bool {
        return self.tick < other.tick;
    }
    pub inline fn deinit(_: @This()) void {}
    pub inline fn getValue(self: @This()) @FieldType(@This(), "tick") {
        return self.tick;
    }
};
pub const TypeIdInt = u32;
