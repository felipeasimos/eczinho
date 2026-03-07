test "components" {
    _ = @import("test_include_components.zig");
    _ = @import("test_include_in_app.zig");
    _ = @import("test_include_duplicate.zig");
}
