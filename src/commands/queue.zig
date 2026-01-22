const std = @import("std");

pub const CommandsQueueOptions = struct {
    Components: type,
    Entity: type,
};

pub fn CommandsQueue(comptime options: CommandsQueueOptions) type {
    return struct {
        pub const Entity = options.Entity;
        pub const Components = options.Components;

        pub const EntityPlaceholder = Entity.Index;

        /// remove component to the entity or placeholder of the current context
        pub const CommandRemove = struct {
            type_id: Components.ComponentTypeId,
        };

        /// add component to the entity or placeholder of the current context
        pub const CommandAdd = struct {
            type_id: Components.ComponentTypeId,
            value: Components.Union,
        };

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

        pub fn useEntity(self: *@This(), entt: Entity) void {
            self.handleContextChange(.{ .entity = entt });
        }

        fn getCurrentContext(self: *@This()) ?Context {
            if (self.current_context_index) |index| {
                return self.commands.items[index].context;
            }
            return null;
        }

        pub fn despawn(self: *@This(), context_id: ContextId) !void {
            if (self.getCurrentContext()) |current_context| {
                if (current_context.id == context_id) {
                    // despawning the current context? Ignore the changes and the context start
                    self.commands.shrinkRetainingCapacity(self.current_context_index.?);
                }
            }
            try self.commands.append(self.allocator, .{ .despawn = .{ .entt = context_id.entity } });
        }
    };
}

test CommandsQueue {
    const EntityTypeFactory = @import("../entity.zig").EntityTypeFactory;
    const Components = @import("../components.zig").Components;
    const typeA = u64;
    const typeB = u32;
    var queue = CommandsQueue(.{
        .Components = Components(&.{ typeA, typeB }),
        .Entity = EntityTypeFactory(.medium),
    }).init(std.testing.allocator);
    defer queue.deinit();
}
