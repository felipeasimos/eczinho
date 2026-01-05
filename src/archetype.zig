const std = @import("std");

pub fn ArchetypeOptions(comptime ComponentTypes: []type) type {
    return struct {
        ComponentBitset: std.StaticBitSet(ComponentTypes.len),
        EntityType: type,
    };
}

pub fn Archetype(comptime World: type) type {
    return struct {
        dense: std.ArrayList(World.Entity.IndexInt),
        sparse: std.ArrayList(World.Entity.IndexInt),
    };
}
