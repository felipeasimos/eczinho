const eczinho = @import("eczinho");
const std = @import("std");

test "AppContextBuilder" {
    const Transform = eczinho.CoreBundles.transform.Transform;
    const typeA = struct { a: f32 };
    const typeB = struct { a: u32 };
    const entity_config: eczinho.entity.EntityOptions = .{ .index_bits = 10, .version_bits = 11 };
    const Context = eczinho.AppContextBuilder.init()
        .addComponent(typeA)
        .addComponents(&.{typeB})
        .addBundle(Transform)
        .setEntityConfig(entity_config)
        .build();
    try std.testing.expect(Context.Components.isComponent(typeA));
    try std.testing.expect(Context.Components.isComponent(typeB));
    try std.testing.expectEqual(eczinho.entity.EntityTypeFactory(entity_config), Context.Entity);
}

test "AppBuilder" {
    const Position = eczinho.CoreBundles.transform.Position;
    const Rotation = eczinho.CoreBundles.transform.Rotation;
    const Transform = eczinho.CoreBundles.transform.Transform;
    const Hierarchy = eczinho.CoreBundles.hierarchy.Hierarchy;
    const ChildConstructor = eczinho.CoreBundles.hierarchy.ChildConstructor;
    const ParentConstructor = eczinho.CoreBundles.hierarchy.ParentConstructor;

    const typeA = struct { a: f32 };
    const typeB = struct { a: u32 };

    const Context = eczinho.AppContextBuilder.init()
        .addBundle(Transform)
        .addBundle(Hierarchy)
        .addComponent(typeA)
        .addComponents(&.{typeB})
        .build();

    try std.testing.expect(Context.Components.isComponent(Position));
    try std.testing.expect(Context.Components.isComponent(Rotation));
    try std.testing.expect(Context.Components.isComponent(ChildConstructor(Context.Entity)));
    try std.testing.expect(Context.Components.isComponent(ParentConstructor(Context.Entity)));

    const Query = Context.Query;

    var test_app = try eczinho.AppBuilder.init(Context)
        .addSystem(.Update, struct {
            pub fn execute(_: Query(.{ .q = &.{ typeA, *typeB } })) void {}
        }.execute)
        .build(std.testing.allocator, std.testing.io);
    defer test_app.deinit();
}
