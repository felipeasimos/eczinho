test "integration tests" {
    _ = @import("test_builder.zig");
    _ = @import("no_systems/tests.zig");
    _ = @import("context/tests.zig");
    _ = @import("systems/tests.zig");
}
