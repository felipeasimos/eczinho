const std = @import("std");
const types = @import("../../types.zig").Tick;
const Table = @import("table.zig").Table;

pub const TablesOptions = struct {
    Entity: type,
    EntityLocation: type,
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
        if (@sizeOf(Component) == 0 and !options.Components.hasAddedMetadata(Component)) continue;

        const Type = Table(.{
            .Entity = options.Entity,
            .EntityLocation = options.EntityLocation,
            .Components = options.Components,
            .Component = Component,
        });
        field_types[i] = Type;
        i += 1;
    }
    return @Tuple(&field_types);
}

pub fn Tables(comptime options: TablesOptions) type {
    const dense_components = options.Components
        .initFull()
        .applyStorageTypeMask(.Dense)
        .applyOccupieSpaceMask();
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
        const EntityLocation = options.EntityLocation;
        const Components = options.Components;
        tables: ComponentArrays = EmptyArrays,
        signature: Components,

        pub fn init(self: *@This(), signature: Components) void {
            return .{
                .signature = signature.applyStorageTypeMask(.Dense).applyOccupieSpaceMask(),
            };
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            inline for (0..ComponentArraysLen) |i| {
                self.tables[i].deinit(allocator);
            }
        }

        fn getTableIndex(comptime Component: type) usize {
            for (0..ComponentArraysLen) |i| {
                const TupleType = @typeInfo(ComponentArrays).@"struct".fields[i].type;
                if (TupleType.Component == Component) {
                    return i;
                }
            }
            @compileError("Shouldn't reach this code line during comptime: Component is not dense, or is a ZST with no metadata attached");
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
            if (comptime ComponentArraysLen == 0) return 0;
            return self.tables[0].data.items.len;
        }
        pub fn add(self: *@This(), allocator: std.mem.Allocator, entt: Entity, value: anytype) !void {
            const table = self.getTable(@TypeOf(value));
            std.debug.assert(!table.contains(entt.index));
            try table.add(allocator, entt.index, value);
        }
        pub fn contains(self: *@This(), entt: Entity, comptime Component: type) bool {
            const table = self.getTable(Component);
            return table.contains(entt.index);
        }
        pub fn remove(self: *@This(), allocator: std.mem.Allocator, entt: Entity) void {
            var 
            for
            const table = self.getTable(Component);
            std.debug.assert(table.contains(entt.index));
            _ = table.remove(entt.index);
        }
        pub fn get(self: *@This(), entt: Entity, comptime Component: type) *Component {
            const table = self.getTable(Component);
            std.debug.assert(table.contains(entt.index));
            return table.get(entt.index);
        }
        pub fn getConst(self: *@This(), entt: Entity, comptime Component: type) Component {
            const table = self.getTable(Component);
            std.debug.assert(table.contains(entt.index));
            return table.getConst(entt.index);
        }
    };
}
