pub const AppBuilder = @import("builder.zig").AppBuilder;
pub const AppContextBuilder = @import("builder.zig").AppContextBuilder;
pub const Commands = @import("commands/factory.zig").CommandsFactory;
pub const EventReader = @import("event/factory.zig").EventReader;
pub const EventWriter = @import("event/factory.zig").EventWriter;
pub const Query = @import("query/factory.zig").QueryFactory;
pub const Resource = @import("resource/factory.zig").ResourceFactory;
pub const SchedulerLabel = @import("scheduler.zig").SchedulerLabel;

test "all" {
    _ = @import("registry.zig").Registry;
    _ = @import("query/query.zig");
    _ = @import("query/factory.zig");
    _ = @import("app.zig");
    _ = @import("builder.zig");
}
