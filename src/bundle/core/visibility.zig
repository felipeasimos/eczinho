const BundleContext = @import("../bundle.zig").BundleContext;
const Bundle = @import("../bundle.zig").Bundle;

pub const Visibility = Bundle{
    .Context = BundleContext.Builder.init()
        .addComponents(&.{Visible})
        .build(),
    .SystemsConstructor = BundleSystems,
};

pub const Visible = enum {
    Visible,
    Hidden,
    Inherited,
};

pub fn BundleSystems(comptime _: type) type {
    return struct {};
}
