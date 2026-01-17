const std = @import("std");

pub const System = struct {
    system: *const anyopaque,
    system_type: type,
    pub fn init(comptime function: anytype) @This() {
        return .{
            .system = &function,
            .system_type = @TypeOf(function),
        };
    }
    pub fn fnPtr(comptime self: @This()) *const self.system_type {
        return @ptrCast(@alignCast(self.system));
    }
    pub fn call(comptime self: @This(), args: anytype) @TypeOf(@call(.auto, self.fnPtr(), args)) {
        return @call(.auto, self.fnPtr(), args);
    }
};

fn testSystem(x: u64) u64 {
    return x + 1;
}

test System {
    const handle = comptime System.init(testSystem);
    comptime {
        try std.testing.expectEqual(@TypeOf(testSystem), handle.system_type);
        try std.testing.expectEqual(testSystem, handle.fnPtr());
        try std.testing.expectEqual(testSystem(234), handle.call(.{234}));
    }
}
