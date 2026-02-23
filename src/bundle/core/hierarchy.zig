const BundleContext = @import("../bundle.zig").BundleContext;
const Bundle = @import("../bundle.zig").Bundle;
const std = @import("std");

pub const Hierarchy = Bundle{
    .ContextConstructor = BundleContextConstructor,
    .FunctionsConstructor = BundleFunctions,
    .SystemsConstructor = BundleSystems,
};

pub fn BundleContextConstructor(comptime Entity: type) BundleContext {
    return BundleContext.Builder.init()
        .addComponent(ParentConstructor(Entity))
        .addComponent(ChildConstructor(Entity))
        .build();
}

pub fn ParentConstructor(comptime Entity: type) type {
    return struct {
        children_ids: std.ArrayList(Entity),
    };
}
pub fn ChildConstructor(comptime Entity: type) type {
    return struct {
        parent_id: Entity,
    };
}
pub fn BundleSystems(comptime _: type) type {
    return struct {};
}
pub fn BundleFunctions(comptime AppContext: type) type {
    return struct {
        const Parent = ParentConstructor(AppContext.Entity);
        pub fn deleteRecursive(comms: AppContext.Commands, parent: Parent) void {
            for (parent.children_ids) |entt| {
                comms.despawn(entt);
            }
        }
    };
}

