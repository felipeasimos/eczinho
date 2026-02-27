pub const AppBuilder = @import("builder.zig").AppBuilder;
pub const AppContextBuilder = @import("builder.zig").AppContextBuilder;
pub const Commands = @import("commands/factory.zig").CommandsFactory;
pub const EventReader = @import("event/factory.zig").EventReader;
pub const EventWriter = @import("event/factory.zig").EventWriter;
pub const Query = @import("query/factory.zig").QueryFactory;
pub const Resource = @import("resource/factory.zig").ResourceFactory;
pub const Removed = @import("removed/factory.zig").Removed;
pub const SchedulerLabel = @import("scheduler.zig").SchedulerLabel;
pub const AppEvents = @import("app_events.zig");

test "eczinho" {
    const std = @import("std");
    _ = @import("chunks.zig");
    std.testing.refAllDeclsRecursive(@This());
}
