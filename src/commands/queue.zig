const std = @import("std");

pub const CommandsQueueOptions = struct {
    Components: type,
    Entity: type,
};

pub fn CommandsQueueFactory(comptime options: CommandsQueueOptions) type {
    return struct {
        pub const Entity = options.Entity;
        pub const Components = options.Components;

        pub const EntityPlaceholder = Entity.Index;

        /// remove component to the entity or placeholder of the current context
        pub const CommandRemove = Components.ComponentTypeId;

        /// add component to the entity or placeholder of the current context
        pub const CommandAdd = Components.Union;

        pub const ContextId = union(enum) {
            entity: Entity,
            placeholder: EntityPlaceholder,
        };

        /// apply following commands to this placeholder entity.
        /// Commands stop being applied to this entity when another context starts or the queue ends.
        /// Ends previous context.
        const Context = struct {
            id: ContextId,
            /// how many queue items are contained inside this context
            size: usize = 0,
        };

        /// despawn an entity.
        /// Ends context.
        /// Note: if this is called for a placeholder, all commands of this context are removed from the queue immediatly
        pub const Despawn = struct { entt: Entity };

        pub const Command = union(enum) {
            add: CommandAdd,
            remove: CommandRemove,
            despawn: Despawn,
            context: Context,
        };

        allocator: std.mem.Allocator,
        commands: std.ArrayList(Command) = .empty,
        next_entity_placeholder: EntityPlaceholder = 0,
        current_context_index: ?usize = null,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.commands.deinit(self.allocator);
        }

        pub fn addCommand(self: *@This(), context: ContextId, command: Command) !void {
            try self.handleContextChange(context);
            try self.commands.append(self.allocator, command);
            // increment context size
            self.commands.items[self.current_context_index.?].context.size += 1;
        }

        pub fn addNewEntity(self: *@This()) !EntityPlaceholder {
            const new_placeholder = self.next_entity_placeholder;
            self.current_context_index = self.commands.items.len;
            try self.commands.append(self.allocator, .{
                .context = .{
                    .id = .{ .placeholder = new_placeholder },
                    .size = 0,
                },
            });
            self.next_entity_placeholder += 1;
            return new_placeholder;
        }

        pub fn despawn(self: *@This(), context_id: ContextId) !void {
            if (self.getCurrentContext()) |current_context| {
                if (std.meta.eql(current_context.id, context_id)) {
                    // despawning the current context? Ignore the changes and the context start
                    self.commands.shrinkRetainingCapacity(self.current_context_index.?);
                }
            }
            try self.commands.append(self.allocator, .{ .despawn = .{ .entt = context_id.entity } });
        }

        pub fn iterator(self: *@This()) Iterator {
            return Iterator.init(self.commands.items);
        }
        pub const Iterator = struct {
            comms: []const Command,
            index: usize = 0,
            pub fn init(comms: []const Command) @This() {
                return .{
                    .comms = comms,
                };
            }
            pub fn next(self: *@This()) ?Command {
                if (self.index >= self.comms.len) return null;
                const i = self.index;
                self.index += 1;
                return self.comms[i];
            }
            pub fn rollback(self: *@This()) void {
                self.index -= 1;
            }
        };

        fn startContext(self: *@This(), new_context_id: ContextId) !void {
            self.current_context_index = self.commands.items.len;
            try self.commands.append(self.allocator, .{
                .context = .{
                    .id = new_context_id,
                    .size = 0,
                },
            });
        }

        fn handleContextChange(self: *@This(), incoming_context_id: ContextId) !void {
            if (self.getCurrentContext()) |current_context| {
                if (std.meta.eql(incoming_context_id, current_context.id)) {
                    return;
                }
            }
            try self.startContext(incoming_context_id);
        }

        fn getCurrentContext(self: *@This()) ?Context {
            if (self.current_context_index) |index| {
                return self.commands.items[index].context;
            }
            return null;
        }
    };
}

test CommandsQueueFactory {
    const Entity = @import("../entity.zig").EntityTypeFactory(.small);
    const Components = @import("../components.zig").Components(&.{ u64, u32 });
    const CommandsQueueType = CommandsQueueFactory(.{
        .Components = Components,
        .Entity = Entity,
    });
    var queue = CommandsQueueType.init(std.testing.allocator);

    const placeholder = try queue.addNewEntity();
    try queue.addCommand(.{ .placeholder = placeholder }, .{ .add = Components.getAsUnion(@as(u64, 8)) });
    try std.testing.expectEqual(2, queue.commands.items.len);

    var iter = queue.iterator();
    try std.testing.expectEqual(CommandsQueueType.Command{
        .context = CommandsQueueType.Context{
            .id = CommandsQueueType.ContextId{ .placeholder = placeholder },
            .size = 1,
        },
    }, iter.next());

    try std.testing.expectEqual(CommandsQueueType.Command{
        .add = Components.getAsUnion(@as(u64, 8)),
    }, iter.next());

    try std.testing.expectEqual(null, iter.next());
    try std.testing.expectEqual(0, queue.current_context_index);

    defer queue.deinit();
}
