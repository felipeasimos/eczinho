const eczinho = @import("eczinho");
const std = @import("std");

test "without non included components" {
    const ComponentA = struct { a: f32 };
    const Context = eczinho.AppContextBuilder.init()
        .build();
    try std.testing.expect(!Context.Components.isComponent(ComponentA));
}

test "with given components" {
    const ComponentA = struct { a: f32 };
    const Context = eczinho.AppContextBuilder.init()
        .addComponent(ComponentA)
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
}

test "include multiple components at once" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const Context = eczinho.AppContextBuilder.init()
        .addComponents(&.{ ComponentA, ComponentB, ComponentC })
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expect(Context.Components.isComponent(ComponentB));
    try std.testing.expect(Context.Components.isComponent(ComponentC));
}

test "include multiple components individually" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const Context = eczinho.AppContextBuilder.init()
        .addComponent(ComponentA)
        .addComponent(ComponentB)
        .addComponent(ComponentC)
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expect(Context.Components.isComponent(ComponentB));
    try std.testing.expect(Context.Components.isComponent(ComponentC));
}

test "include components individually and at once" {
    const ComponentA = struct { a: f32 };
    const ComponentB = struct { a: u31 };
    const ComponentC = struct { a: u30 };
    const Context = eczinho.AppContextBuilder.init()
        .addComponents(&.{ ComponentA, ComponentB })
        .addComponent(ComponentC)
        .build();
    try std.testing.expect(Context.Components.isComponent(ComponentA));
    try std.testing.expect(Context.Components.isComponent(ComponentB));
    try std.testing.expect(Context.Components.isComponent(ComponentC));
}
