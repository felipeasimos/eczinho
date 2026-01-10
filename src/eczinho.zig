const std = @import("std");

pub const registry = @import("registry.zig");
pub const entity = @import("entity.zig");

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
    _ = @import("sparse_set.zig");
}

