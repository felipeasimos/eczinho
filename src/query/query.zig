pub const Factory = @import("factory.zig").QueryFactory;
pub const Request = @import("request.zig").QueryRequest;
pub const Mut = @import("mut.zig").Mut;

pub fn isQuery(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and
        @hasDecl(T, "Marker") and
        @TypeOf(T.Marker) == @TypeOf(Factory) and
        T.Marker == Factory;
}
