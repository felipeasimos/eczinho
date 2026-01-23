const std = @import("std");
const SchedulerLabel = @import("scheduler.zig").SchedulerLabel;

pub const System = struct {
    system: *const anyopaque,
    system_type: type,
    scheduler_label: SchedulerLabel,
    args_tuple_type: type,
    param_types: []const type,

    fn getParamTypes(comptime FuncType: type) []const type {
        const type_info = @typeInfo(FuncType);
        if (type_info != .@"fn") {
            @compileError("Systems should be a function type");
        }
        const fn_info = @typeInfo(FuncType).@"fn";
        var params: []const type = &.{};
        for (fn_info.params) |param| {
            const ParameterType = param.type.?;
            params = params ++ .{ParameterType};
        }
        return params;
    }

    pub fn init(comptime label: SchedulerLabel, comptime function: anytype) @This() {
        return .{
            .system = &function,
            .system_type = @TypeOf(function),
            .scheduler_label = label,
            .param_types = getParamTypes(@TypeOf(function)),
            .args_tuple_type = std.meta.ArgsTuple(@TypeOf(function)),
        };
    }
    pub inline fn fnPtr(comptime self: @This()) *const self.system_type {
        return @ptrCast(@alignCast(self.system));
    }
    pub inline fn call(comptime self: @This(), args: anytype) @TypeOf(@call(.auto, self.fnPtr(), args)) {
        return @call(.auto, self.fnPtr(), args);
    }
};

const AppContext = @import("app.zig").AppContext;
const EntityTypeFactory = @import("entity.zig").EntityTypeFactory;
const Components = @import("components.zig").Components;

const Query = AppContext(.{
    .Components = Components(&.{ u8, u16, u32, u64 }),
    .Entity = EntityTypeFactory(.medium),
}).Query;

fn testSystem(x: Query(.{ .q = &.{ u8, *u16, ?*u32, *const u64 } })) void {
    _ = x;
}

test System {
    const handle = comptime System.init(.Update, testSystem);
    try std.testing.expectEqual(@TypeOf(testSystem), handle.system_type);
    try std.testing.expectEqual(testSystem, handle.fnPtr());
}
