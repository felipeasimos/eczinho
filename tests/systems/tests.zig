test "tests with systems" {
    _ = @import("test_spawn_deferred.zig");
    _ = @import("test_close_application.zig");
    _ = @import("components/tests.zig");
    _ = @import("query/tests.zig");
    _ = @import("events/tests.zig");
}
