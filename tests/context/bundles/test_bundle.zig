const eczinho = @import("eczinho");
const std = @import("std");

test "completely default bundles are not unique because function bodies are the same" {
    const bundleA: eczinho.Bundle = .{};
    const bundleB: eczinho.Bundle = .{};
    try std.testing.expect(bundleA.eql(bundleB));
}

test "non-default bundles are unique because function bodies are unique" {
    const bundleA: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build(Entity);
            }
        }).constructor,
    };
    const bundleB: eczinho.Bundle = .{
        .ContextConstructor = (struct {
            pub fn constructor(comptime Entity: type) eczinho.BundleContext {
                return eczinho.BundleContext.Builder.init()
                    .build(Entity);
            }
        }).constructor,
    };
    try std.testing.expect(!bundleA.eql(bundleB));
}
