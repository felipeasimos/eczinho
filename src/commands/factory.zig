const CommandsQueueFactory = @import("queue.zig").CommandsQueue;
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
        pub const CommandsQueue = CommandsQueueFactory(.{
            .Components = Components,
            .Entity = Entity,
        });

        queue_index: usize,
        reg: *Registry,

        pub fn init(reg: *Registry) !@This() {
            return .{
                .queue_index = try reg.createQueue(),
                .reg = reg,
            };
        }
        pub fn deinit(self: @This()) void {
            _ = self;
        }
        fn getQueue(self: @This()) *CommandsQueue {
            return self.reg.getQueue(self.queue_index);
        }
        pub fn add(self: @This(), entt: Entity, value: anytype) void {
            return self.getQueue().addCommand(.{ .entity = entt }, .{
                .add = Components.getAsUnion(value),
            }) catch @panic("Commands `add` error because of ArrayList.append");
        }
        pub fn remove(self: @This(), comptime Component: type, entt: Entity) void {
            self.getQueue().addCommand(.{ .entity = entt }, .{
                .remove = Components.hash(Component),
            }) catch @panic("Commands `remove` error because of ArrayList.append");
        }
        pub fn despawn(self: @This(), entt: Entity) void {
            self.getQueue().despawn(.{ .entity = entt }) catch @panic("Commands `despawn` error because of ArrayList.append");
        }
        pub fn spawn(self: @This()) EntityCommands {
            const new_entt = self.getQueue().addNewEntity() catch @panic("Commands `spawn` shouldn't error out. This is a bug or a mishandling of the library");
            return EntityCommands.init(self, .{ .placeholder = new_entt });
        }
        pub fn entity(self: @This(), entt: Entity) EntityCommands {
            return EntityCommands.init(self, .{ .entity = entt });
        }

        pub const EntityCommands = struct {
            commands: Commands,
            entt: CommandsQueue.ContextId,
            pub fn init(comm: Commands, entt: CommandsQueue.ContextId) @This() {
                return .{ .commands = comm, .entt = entt };
            }
            pub fn add(self: @This(), value: anytype) @This() {
                self.commands.getQueue().addCommand(self.entt, .{
                    .add = Components.getAsUnion(value),
                }) catch @panic("EntityCommands `add` shouldn't error out. This is a bug or a mishandling of the library");
                return self;
            }
        };
    };
}
