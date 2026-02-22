const BundleContext = @import("../bundle.zig").BundleContext;
const Bundle = @import("../bundle.zig").Bundle;

pub const Transform = Bundle{
    .ContextConstructor = BundleContextConstructor,
    .SystemsConstructor = BundleSystems,
};

pub fn BundleContextConstructor(comptime _: type) BundleContext {
    return BundleContext.Builder.init()
        .addComponents(&.{ Position, Rotation })
        .build();
}

pub fn BundleSystems(comptime _: type) type {
    return struct {};
}

pub const Position = struct {
    x: f32,
    y: f32,
};

pub const Rotation = struct {
    angle: f32,
};

pub const Scale = struct {
    x: f32,
    y: f32,
};
