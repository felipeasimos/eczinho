test "bundles" {
    _ = @import("test_bundle.zig");
    _ = @import("test_include_bundles.zig");
    _ = @import("components/tests.zig");
    _ = @import("events/tests.zig");
    _ = @import("resources/tests.zig");
}
