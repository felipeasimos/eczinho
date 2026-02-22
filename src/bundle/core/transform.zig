const BundleContext = @import("../bundle.zig").BundleContext;
const Bundle = @import("../bundle.zig").Bundle;

pub const Transform2D = Bundle{
    .Context = BundleContext.Builder.init()
        .addComponents(&.{ Position, Rotation })
        .build(),
    .SystemsConstructor = BundleSystems,
};

pub const Position = struct {
    x: f32,
    y: f32,
};

pub const Rotation = struct {
    angle: f32,
};

pub fn BundleSystems(comptime _: type) type {
    return struct {};
}
