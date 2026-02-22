const BundleContext = @import("../bundle.zig").BundleContext;
const Bundle = @import("../bundle.zig").Bundle;
const Transform2D = @import("transform.zig").Transform2D;
const Position = @import("transform.zig").Position;
const StageLabel = @import("../../stage_label.zig").StageLabel;

pub const Velocity = struct {
    x: f32,
    y: f32,
};

pub const Euclidian = Bundle{
    .Context = BundleContext.Builder.init()
        .addBundle(Transform2D)
        .addComponent(Velocity)
        .build(),
    .SystemsConstructor = BundleSystems,
};

pub fn BundleSystems(comptime AppContext: type) type {
    return struct {
        const Query = AppContext.Query;

        pub const moveStage: StageLabel = .Update;
        pub fn move(q: Query(.{ .q = &.{ *Position, Velocity } })) !void {
            var iter = q.iter();
            while (iter.next()) |tuple| {
                const pos_ptr, const vel = tuple;
                pos_ptr.x += vel.x;
                pos_ptr.y += vel.y;
            }
        }
    };
}
