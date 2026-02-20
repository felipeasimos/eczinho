const CommandsQueueFactory = @import("queue.zig").CommandsQueueFactory;

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
        pub const CommandsQueue = CommandsQueueFactory(.{
            .Components = Components,
            .Entity = Entity,
        });

        queue: *CommandsQueue,

        pub fn init(queue: *CommandsQueue) !@This() {
            return .{
                .queue = queue,
            };
        }
        pub fn deinit(self: @This()) void {
            _ = self;
        }
        inline fn getQueue(self: @This()) *CommandsQueue {
            return self.queue;
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

test CommandsFactory {
    const std = @import("std");
    const Entity = @import("../entity.zig").EntityTypeFactory(.small);
    const Components = @import("../components.zig").Components(&.{ u64, u32 });
    const CommandsQueueType = CommandsQueueFactory(.{
        .Components = Components,
        .Entity = Entity,
    });
    const CommandsType = CommandsFactory(.{ .Entity = Entity, .Components = Components });
    var queue = CommandsQueueType.init(std.testing.allocator);
    defer queue.deinit();

    var commands = try CommandsType.init(&queue);
    _ = commands.spawn()
        .add(@as(u64, 7));

    defer commands.deinit();
}
