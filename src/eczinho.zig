const std = @import("std");

pub const registry = @import("registry.zig");
pub const entity = @import("entity.zig");
pub const App = @import("app.zig").App;

pub fn Eczinho(comptime registry_options: registry.RegistryOptions) type {
    return struct {
        allocator: std.mem.Allocator,
        registry: registry.Registry(registry_options),
        pub const Registry = @FieldType(@This(), "registry");

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
                .registry = Registry.init(alloc),
            };
        }
    };
}

test Eczinho {
    _ = @import("registry.zig").Registry;
    _ = @import("query/query.zig");
    _ = @import("query/factory.zig");
    _ = @import("app.zig");
    _ = @import("builder.zig");
}
