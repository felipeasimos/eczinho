const std = @import("std");
const Request = @import("request.zig").QueryRequest;
const utils = @import("utils.zig");

pub const QueryFactoryOptions = struct {
    request: Request,
    EntityType: type,
    ComponentBitSet: type,
};

/// use in systems to obtain a query. System signature should be like:
/// fn systemExample(q: Query(.{.q = &.{typeA, *typeB}, .with = &.{typeC}}) !void {
///     ...
/// }
/// checkout QueryRequest for more information
pub fn QueryFactory(comptime options: QueryFactoryOptions) type {
    const ComponentBitSet = options.ComponentBitSet;
    const req = options.request;
    var fields: [req.q.len]std.builtin.Type.StructField = undefined;
    for (req.q, 0..) |AccessibleType, i| {
        const CanonicalType = utils.getCanonicalQueryType(AccessibleType);
        ComponentBitSet.checkSize(CanonicalType);
        fields[i] = std.builtin.Type.StructField{
            .name = std.fmt.comptimePrint("{}", .{i}),
            .type = AccessibleType,
            .is_comptime = false,
            .default_value_ptr = null,
            .alignment = @alignOf(AccessibleType),
        };
    }
    const SingleType = req.q[0];
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
        pub fn init() @This() {}
        pub fn empty(self: *@This()) bool {}
        pub fn single(self: *@This()) SingleType {}
        pub fn iter(self: *@This()) ?ResultTuple {}
    };
}
