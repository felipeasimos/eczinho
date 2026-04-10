test "query" {
    _ = @import("test_added.zig");
    _ = @import("test_changed.zig");
    _ = @import("test_removed.zig");
    _ = @import("test_access_types.zig");
    _ = @import("test_partial_optional_access.zig");
}
