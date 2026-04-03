const std = @import("std");
const types = @import("../../types.zig");

pub const TableOptions = struct {
    Components: type,
    Component: type,
};

fn CreateTableData(comptime options: TableOptions) type {
    var field_names: []const []const u8 = &.{};
    var field_types: []const type = &.{};
    var field_attrs: []const std.builtin.Type.StructField.Attributes = &.{};

    if (@sizeOf(options.Component) != 0) {
        field_names = field_names ++ .{"data"};
        field_types = field_types ++ .{std.ArrayList(options.Component)};
        field_attrs = field_attrs ++ .{
            std.builtin.Type.StructField.Attributes{
                .default_value_ptr = &std.ArrayList(options.Component).empty,
            },
        };
    }

    if (options.Components.hasAddedMetadata(options.Component)) {
        field_names = field_names ++ .{"added"};
        field_types = field_types ++ .{std.ArrayList(types.Tick)};
        field_attrs = field_attrs ++ .{
            std.builtin.Type.StructField.Attributes{
                .default_value_ptr = &std.ArrayList(types.Tick).empty,
            },
        };
    }

    if (options.Components.hasChangedMetadata(options.Component)) {
        field_names = field_names ++ .{"changed"};
        field_types = field_types ++ .{std.ArrayList(types.Tick)};
        field_attrs = field_attrs ++ .{
            std.builtin.Type.StructField.Attributes{
                .default_value_ptr = &std.ArrayList(types.Tick).empty,
            },
        };
    }

    return @Struct(
        .auto,
        null,
        field_names,
        &(field_types[0..field_types.len].*),
        &(field_attrs[0..field_attrs.len].*),
    );
}

pub fn Table(comptime options: TableOptions) type {
    return struct {
        pub const Components = options.Components;
        pub const Component = options.Component;
        pub const Data = CreateTableData(options);
        pub const empty: @This() = .{};
        data: Data = .{},

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (comptime @sizeOf(Component) != 0) {
                self.data.data.deinit(allocator);
            }
            if (comptime Components.hasAddedMetadata(Component)) {
                self.data.added.deinit(allocator);
            }
            if (comptime Components.hasChangedMetadata(Component)) {
                self.data.changed.deinit(allocator);
            }
        }
        pub fn contains(self: *@This(), index: usize) bool {
            if (comptime @sizeOf(Component) != 0) {
                return index < self.data.data.items.len;
            }
            if (comptime Components.hasAddedMetadata(Component)) {
                return index < self.data.added.len;
            }
            if (comptime Components.hasChangedMetadata(Component)) {
                return index < self.data.changed.len;
            }
            @compileError("This table for type " ++ @typeName(Component) ++
                " shouldn't even exist. It occupies no space, even for metadata!");
        }

        pub fn get(self: *@This(), index: usize) *Component {
            return &self.data.data.items[index];
        }
        pub fn getConst(self: *@This(), index: usize) Component {
            return self.data.data.items[index];
        }
        pub fn reserve(self: *@This(), allocator: std.mem.Allocator) !void {
            if (comptime @sizeOf(Component) != 0) {
                // SAFETY: `get` will be called after to set the value
                try self.data.data.append(allocator, undefined);
            }
            if (comptime Components.hasAddedMetadata(Component)) {
                // SAFETY: `get` will be called after to set the value
                try self.data.added.append(allocator, undefined);
            }
            if (comptime Components.hasChangedMetadata(Component)) {
                // SAFETY: `get` will be called after to set the value
                try self.data.changed.append(allocator, undefined);
            }
        }
        pub fn len(self: *const @This()) usize {
            if (comptime @sizeOf(Component) != 0) {
                return self.data.data.items.len;
            } else if (comptime Components.hasAddedMetadata(Component)) {
                return self.data.added.items.len;
            } else if (comptime Components.hasChangedMetadata(Component)) {
                return self.data.changed.items.len;
            }
            @compileError("No way to get length of table of component '" ++ @typeName(Component) ++ "'");
        }
        pub fn remove(self: *@This(), index: usize) void {
            if (comptime @sizeOf(Component) != 0) {
                _ = self.data.data.swapRemove(index);
            }
            if (comptime Components.hasAddedMetadata(Component)) {
                _ = self.data.added.swapRemove(index);
            }
            if (comptime Components.hasChangedMetadata(Component)) {
                _ = self.data.changed.swapRemove(index);
            }
        }
        pub fn getAddedArray(self: *@This()) []types.Tick {
            if (comptime Components.hasAddedMetadata(Component)) {
                return self.data.added.items;
            }
            @compileError("Tabled Component doesn't have `added` metadata");
        }
        pub fn getChangedArray(self: *@This()) []types.Tick {
            if (comptime Components.hasChangedMetadata(Component)) {
                return self.data.changed.items;
            }
            @compileError("Tabled Component doesn't have `changed` metadata");
        }
    };
}
