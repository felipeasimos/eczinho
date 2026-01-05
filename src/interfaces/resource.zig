pub const Resource = struct {
    pub fn init(dependencies: anytype) !@This() {
        _ = dependencies;
        return .{};
    }
    pub fn execute(self: *@This()) !void {
        _ = self;
    }
};
