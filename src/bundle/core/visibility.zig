const BundleContext = @import("../bundle.zig").BundleContext;
const Bundle = @import("../bundle.zig").Bundle;

pub const Visibility = Bundle{
    .ContextConstructor = BundleContextConstructor,
    .SystemsConstructor = BundleSystems,
};

pub const Visible = enum {
    Visible,
    Hidden,
    Inherited,
};

pub fn BundleContextConstructor(comptime Entity: type) BundleContext {
    return BundleContext.Builder.init()
        .addComponents(&.{Visible})
        .build(Entity);
}

pub fn BundleSystems(comptime _: type) type {
    return struct {};
}
