const eczinho = @import("eczinho");
const std = @import("std");

test "without non included resources" {
    const ResourceA = struct { a: f32 };
    const Context = eczinho.AppContextBuilder.init()
        .build();
    try std.testing.expect(!Context.Resources.isResource(ResourceA));
}

test "with given resources" {
    const ResourceA = struct { a: f32 };
    const Context = eczinho.AppContextBuilder.init()
        .addResource(ResourceA)
        .build();
    try std.testing.expect(Context.Resources.isResource(ResourceA));
}

test "include multiple resources at once" {
    const ResourceA = struct { a: f32 };
    const ResourceB = struct { a: u31 };
    const ResourceC = struct { a: u30 };
    const Context = eczinho.AppContextBuilder.init()
        .addResources(&.{ ResourceA, ResourceB, ResourceC })
        .build();
    try std.testing.expect(Context.Resources.isResource(ResourceA));
    try std.testing.expect(Context.Resources.isResource(ResourceB));
    try std.testing.expect(Context.Resources.isResource(ResourceC));
}

test "include multiple resources individually" {
    const ResourceA = struct { a: f32 };
    const ResourceB = struct { a: u31 };
    const ResourceC = struct { a: u30 };
    const Context = eczinho.AppContextBuilder.init()
        .addResource(ResourceA)
        .addResource(ResourceB)
        .addResource(ResourceC)
        .build();
    try std.testing.expect(Context.Resources.isResource(ResourceA));
    try std.testing.expect(Context.Resources.isResource(ResourceB));
    try std.testing.expect(Context.Resources.isResource(ResourceC));
}

test "include resources individually and at once" {
    const ResourceA = struct { a: f32 };
    const ResourceB = struct { a: u31 };
    const ResourceC = struct { a: u30 };
    const Context = eczinho.AppContextBuilder.init()
        .addResources(&.{ ResourceA, ResourceB })
        .addResource(ResourceC)
        .build();
    try std.testing.expect(Context.Resources.isResource(ResourceA));
    try std.testing.expect(Context.Resources.isResource(ResourceB));
    try std.testing.expect(Context.Resources.isResource(ResourceC));
}
