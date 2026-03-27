const std = @import("std");
const types = @import("../../types.zig").Tick;

pub const TableOptions = struct {
    Entity: type,
    EntityLocation: type,
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

    if (options.Components.hasAddedMetatadata(options.Component)) {
        field_names = field_names ++ .{"added"};
        field_types = field_types ++ .{std.ArrayList(types.Tick)};
        field_attrs = field_attrs ++ .{
            std.builtin.Type.StructField.Attributes{
                .default_value_ptr = &std.ArrayList(types.Tick).empty,
            },
        };
    }

    if (options.Components.hasChangedMetatadata(options.Component)) {
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
        &field_types,
        &field_attrs,
    );
}

pub fn Table(comptime options: TableOptions) type {
    return struct {
        pub const Components = options.Components;
        pub const Component = options.Component;
        pub const Data = CreateTableData(options);
        pub const empty: @This() = .{};
        data: Data = .{},

        pub fn contains(self: *@This(), index: usize) bool {
            if (comptime @sizeOf(Component) != 0) {
                return index < self.data.items.len;
            }
            if (comptime Components.hasAddedMetadata(Component)) {
                return index < self.data.added.len;
            }
            @compileError("This table for type " ++ @typeName(Component) ++
                " shouldn't even exist. It occupies no space, even for metadata!");
        }
    };
}
