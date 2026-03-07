const std = @import("std");
test "integration tests" {
    _ = @import("test_builder.zig");
    _ = @import("no_systems/tests.zig");
    _ = @import("context/tests.zig");
    std.testing.refAllDeclsRecursive(@This());
}
