pub const Removed = @import("factory.zig").Removed;
pub const RemovedLog = @import("removed_log.zig").RemovedComponentsLog;

pub fn isRemoved(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and
        @hasDecl(T, "Marker") and
        @TypeOf(T.Marker) == @TypeOf(Removed) and
        T.Marker == Removed;
}
