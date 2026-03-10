test "query" {
    _ = @import("test_added.zig");
    _ = @import("test_changed.zig");
    _ = @import("test_removed.zig");
}
