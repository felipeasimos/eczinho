const std = @import("std");
const Request = @import("request.zig").QueryRequest;
const ComponentsFactory = @import("../components.zig").Components;
const EntityFactory = @import("../entity.zig").EntityTypeFactory;
const archetype = @import("../archetype.zig");
const registry = @import("../registry.zig");

pub const CommandsFactoryOptions = struct {
    Entity: type,
    Components: type,
};

/// use in systems to obtain a query. System signature should be like:
/// fn systemExample(commands: Commands) !void {
///     ...
/// }
/// checkout QueryRequest for more information
pub fn CommandsFactory(comptime options: CommandsFactoryOptions) type {
    return struct {
        const Commands = @This();
        /// used to acknowledge that this type came from QueryFactory()
        pub const Marker = CommandsFactory;
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const Registry = registry.Registry(.{
            .Entity = Entity,
            .Components = Components,
        });

        pub fn add(self: *@This(), entt: Entity, value: anytype) void {}
        pub fn remove(self: *@This(), entt: Entity, comptime Component: type) void {}
        pub fn spawnWith(self: *@This(), values: anytype) void {}
        pub fn despawn(self: *@This(), entt: Entity) void {}
        pub fn entity(self: *@This(), entt: Entity) EntityCommands {}
        pub fn spawn(self: *@This()) EntityCommands {}
        pub fn flush(self: *@This(), reg: *Registry) void {}

        pub const EntityCommands = struct {
            commands: *Commands,
            entt: Entity,
            pub fn init(comm: *Commands, entity: Entity) @This() {
                return .{ .commands = comm, .entity = Entity };
            }
            pub fn add(
        };
    };
}
