const Query = @import("../query/query.zig").Query;

pub const System = struct {
    // exampleSystem(Query(.{}))
    pub fn execute(comptime query: anytype) !void {
        _ = query;
    }
};
