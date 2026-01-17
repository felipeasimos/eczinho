const AppOptions = @import("app.zig").AppOptions;

pub const SchedulerLabel = enum {
    Startup,
    Update,
    Render,
};

pub const SchedulerOptions = struct {};

pub fn Scheduler(comptime options: AppOptions) type {
    return struct {
        pub const Components = options.Context.Components;
        pub const Entity = options.Context.Entity;
    };
}
