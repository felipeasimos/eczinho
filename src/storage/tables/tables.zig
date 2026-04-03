const std = @import("std");
const Table = @import("table.zig").Table;
const types = @import("../../types.zig");

pub const TablesOptions = struct {
    Entity: type,
    Components: type,
};

fn CreateComponentArraysTupleType(
    comptime options: TablesOptions,
    comptime dense_components: options.Components,
) type {
    var field_types: [dense_components.len()]type = undefined;
    var iter = comptime dense_components.iterator();
    var i = 0;
    inline while (iter.nextTypeId()) |tid| {
        const Component = options.Components.getType(tid);
        // don't even create fields for ZSTs with no metadata
        if (!options.Components.DenseOccupiesSpaceComponents.has(Component)) continue;

        const Type = Table(.{
            .Components = options.Components,
            .Component = Component,
        });
        field_types[i] = Type;
        i += 1;
    }
    return @Tuple(&field_types);
}

pub fn TablesFactory(comptime options: TablesOptions) type {
    const dense_components = options.Components
        .initFull()
        .applyStorageTypeMask(.Dense)
        .applyOccupiesSpaceMask();
    const ComponentArrays = CreateComponentArraysTupleType(options, dense_components);
    const ComponentArraysLen = @typeInfo(ComponentArrays).@"struct".fields.len;

    const EmptyArrays = EmptyArrays: {
        // SAFETY: filled immediatly after
        var sets: ComponentArrays = undefined;
        for (0..ComponentArraysLen) |i| {
            sets[i] = .empty;
        }
        break :EmptyArrays sets;
    };
    return struct {
        const Entity = options.Entity;
        const Components = options.Components;
        pub const Storage = @This();
        pub const StorageAddress = struct { *@This(), usize };
        pub const RemovalResult = struct {
            usize,
            usize,
        };
        pub const Tables = @This();
        tables: ComponentArrays = EmptyArrays,
        /// read only pointer to the entities array in the archetype
        entities: *const std.ArrayList(Entity),
        signature: Components,
        count: usize = 0,

        pub inline fn init(signature: Components) !@This() {
            return .{
                .signature = signature.intersection(comptime Components.DenseOccupiesSpaceComponents),
                // SAFETY: set in `postInit`
                .entities = undefined,
            };
        }
        pub inline fn postInit(self: *@This(), archetype_ptr: anytype) void {
            self.entities = &archetype_ptr.entities;
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            inline for (0..ComponentArraysLen) |i| {
                self.tables[i].deinit(allocator);
            }
        }

        fn getTableIndex(tid_or_component: anytype) usize {
            if (comptime @TypeOf(tid_or_component) == type) {
                if (!Components.DenseOccupiesSpaceComponents.has(tid_or_component)) {
                    @compileError("Shouldn't reach this code line during comptime:" ++
                        " Component is not dense, or is a ZST with no metadata attached");
                }
            }
            return Components.DenseOccupiesSpaceComponents.getIndexInSet(tid_or_component);
        }
        fn GetTableResultType(comptime Component: type) type {
            const index = getTableIndex(Component);
            return @typeInfo(ComponentArrays).@"struct".fields[index].type;
        }
        fn getTable(self: *@This(), comptime Component: type) *GetTableResultType(Component) {
            const index = comptime getTableIndex(Component);
            return &self.tables[index];
        }
        pub fn len(self: *const @This()) usize {
            return self.count;
        }
        pub fn reserve(self: *@This(), allocator: std.mem.Allocator, _: Entity) !StorageAddress {
            const index = self.len();
            comptime var iter = Components.DenseOccupiesSpaceComponents.iterator();
            inline while (comptime iter.nextTypeId()) |tid| {
                const Component = comptime Components.getType(tid);
                if (self.signature.has(Component)) {
                    const table = self.getTable(Component);
                    try table.reserve(allocator);
                }
            }
            self.count += 1;
            return .{ self, index };
        }
        pub fn remove(self: *@This(), allocator: std.mem.Allocator, index: usize) !?RemovalResult {
            _ = allocator;
            if (comptime Components.Len == 0) return null;
            comptime var iter = Components.DenseOccupiesSpaceComponents.iterator();
            inline while (comptime iter.nextTypeId()) |tid| {
                const Component = comptime Components.getType(tid);
                if (self.signature.has(Component)) {
                    const table = self.getTable(Component);
                    std.debug.assert(table.contains(index));
                    table.remove(index);
                }
            }
            self.count -= 1;
            if (index == self.entities.items.len - 1) return null;
            const swapped_entt = self.entities.items[self.entities.items.len - 1];
            return .{ swapped_entt.index, index };
        }
        pub inline fn getComponentWithTypeId(self: *@This(), tid: Components.ComponentTypeId, index: usize) []u8 {
            if (comptime ComponentArraysLen == 0) return &.{};
            const table_index = getTableIndex(tid);
            return switch (table_index) {
                inline 0...(ComponentArraysLen - 1) => |table_idx| ret: {
                    const slice = self.tables[table_idx].get(index);
                    break :ret @alignCast(std.mem.asBytes(slice));
                },
                else => @panic("invalid component type id for table storage"),
            };
        }
        pub fn get(self: *@This(), comptime Component: type, index: usize) *Component {
            const table = self.getTable(Component);
            std.debug.assert(table.contains(index));
            return table.get(index);
        }
        pub fn getConst(self: *@This(), comptime Component: type, index: usize) Component {
            if (comptime Component == Entity) {
                return self.entities.items[index];
            }
            const table = self.getTable(Component);
            std.debug.assert(table.contains(index));
            return table.getConst(index);
        }
        pub fn getAddedArray(self: *@This(), tid: Components.ComponentTypeId) []types.Tick {
            if (comptime ComponentArraysLen == 0) return &.{};
            const table_index = getTableIndex(tid);
            return switch (table_index) {
                inline 0...(ComponentArraysLen - 1) => |table_idx| ret: {
                    const table = &self.tables[table_idx];
                    const Component = @TypeOf(table.*).Component;
                    if (comptime Components.hasAddedMetadata(Component)) {
                        break :ret table.getAddedArray();
                    }
                    break :ret &.{};
                },
                else => @panic("invalid component type id for table storage"),
            };
        }
        pub fn getChangedArray(self: *@This(), tid: Components.ComponentTypeId) []types.Tick {
            if (comptime ComponentArraysLen == 0) return &.{};
            const table_index = getTableIndex(tid);
            return switch (table_index) {
                inline 0...(ComponentArraysLen - 1) => |table_idx| ret: {
                    const table = &self.tables[table_idx];
                    const Component = @TypeOf(table.*).Component;
                    if (comptime Components.hasChangedMetadata(Component)) {
                        break :ret table.getChangedArray();
                    }
                    break :ret &.{};
                },
                else => @panic("invalid component type id for table storage"),
            };
        }

        pub const Iterator = struct {
            index: usize = 0,
            tables: *Tables,
            pub fn init(tables: *Tables) @This() {
                return .{
                    .tables = tables,
                };
            }
            pub fn next(self: *@This()) ?StorageAddress {
                if (self.index == self.tables.len()) return null;
                const ret = self.index;
                self.index += 1;
                return .{ self.tables, ret };
            }
            pub fn peek(self: *@This()) ?StorageAddress {
                if (self.index == self.tables.len()) return null;
                return .{ self.tables, self.index };
            }
        };
    };
}
