const std = @import("std");
const Request = @import("request.zig").QueryRequest;
const ComponentsFactory = @import("../components.zig").Components;
const EntityFactory = @import("../entity.zig").EntityTypeFactory;
const utils = @import("utils.zig");

pub const QueryFactoryOptions = struct {
    request: Request,
    Entity: type,
    Components: type,
};

/// use in systems to obtain a query. System signature should be like:
/// fn systemExample(q: Query(.{.q = &.{typeA, *typeB}, .with = &.{typeC}}) !void {
///     ...
/// }
/// checkout QueryRequest for more information
pub fn QueryFactory(comptime options: QueryFactoryOptions) type {
    const Components = options.Components;

    const req = options.request;
    var fields: [req.q.len]std.builtin.Type.StructField = undefined;
    for (req.q, 0..) |AccessibleType, i| {
        const CanonicalType = utils.getCanonicalQueryType(AccessibleType);
        Components.checkSize(CanonicalType);
        fields[i] = std.builtin.Type.StructField{
            .name = std.fmt.comptimePrint("{}", .{i}),
            .type = AccessibleType,
            .is_comptime = false,
            .default_value_ptr = null,
            .alignment = @alignOf(AccessibleType),
        };
    }
    const ResultTuple = @Type(std.builtin.Type{
        .@"struct" = .{
            .layout = .auto,
            .is_tuple = true,
            .fields = &fields,
            .decls = &.{},
        },
    });
    return struct {
        /// used to acknowledge that this type came from QueryFactory()
        pub const Marker = QueryFactory;
        pub const Single = req.q[0];
        pub const Tuple = ResultTuple;

        pub fn init() @This() {}
        pub fn empty(_: *@This()) bool {}
        pub fn single(_: *@This()) Single {}
        pub fn iter(_: *@This()) ?Tuple {}
    };
}

test QueryFactory {
    const camelCase1 = u31;
    const camelCase2 = u32;
    const camelCase3 = u33;
    const camelCase4 = u34;
    const camelCase5 = u35;
    const PascalCase1 = u36;
    const PascalCase2 = u37;
    const PascalCase3 = u38;
    const PascalCase4 = u39;
    const PascalCase5 = u40;
    const Query = QueryFactory(.{
        .request = .{
            .q = &.{
                camelCase1,
                *camelCase2,
                ?*camelCase3,
                *const camelCase4,
                ?*const camelCase5,
                PascalCase1,
                *PascalCase2,
                ?*PascalCase3,
                *const PascalCase4,
                ?*const PascalCase5,
            },
            .with = &.{ u32, f32 },
            .without = &.{u41},
        },
        .Components = ComponentsFactory(&.{
            camelCase1,
            camelCase2,
            camelCase3,
            camelCase4,
            camelCase5,
            PascalCase1,
            PascalCase2,
            PascalCase3,
            PascalCase4,
            PascalCase5,
        }),
        .Entity = EntityFactory(.medium),
    });
    try std.testing.expectEqual(u31, @FieldType(Query.Tuple, "0"));
    try std.testing.expectEqual(*u32, @FieldType(Query.Tuple, "1"));
    try std.testing.expectEqual(?*u33, @FieldType(Query.Tuple, "2"));
    try std.testing.expectEqual(*const u34, @FieldType(Query.Tuple, "3"));
    try std.testing.expectEqual(?*const u35, @FieldType(Query.Tuple, "4"));

    try std.testing.expectEqual(u36, @FieldType(Query.Tuple, "5"));
    try std.testing.expectEqual(*u37, @FieldType(Query.Tuple, "6"));
    try std.testing.expectEqual(?*u38, @FieldType(Query.Tuple, "7"));
    try std.testing.expectEqual(*const u39, @FieldType(Query.Tuple, "8"));
    try std.testing.expectEqual(?*const u40, @FieldType(Query.Tuple, "9"));
}
