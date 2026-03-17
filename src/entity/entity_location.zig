const std = @import("std");

pub const EntityLocationOptions = struct {
    Archetype: type,
    Entity: type,
};

pub fn EntityLocation(comptime options: EntityLocationOptions) type {
    return struct {
        pub const Archetype = options.Archetype;
        pub const Entity = options.Entity;
        pub const Chunk = Archetype.Chunk;
        pub const Components = Archetype.Components;

        // pointer to archetype
        arch: *Archetype,
        // points to chunk, if any component is stored in one.
        // this is unused for table and sparse set storages
        chunk: *Archetype.Chunk,
        // slot index inside the chunk
        chunk_slot_index: u16,
        // table index
        table_index: usize = 0,
        // dense index of the sparse set
        dense_index: usize = 0,
        // current (if alive) or next (if dead) generation of an entity index.
        version: options.Entity.Version = 0,

        pub inline fn valid(arr: *std.ArrayList(@This()), id: Entity) bool {
            if (id.index >= arr.items.len) return false;
            return arr.items[id.index].version == id.version;
        }
        pub inline fn getEntityArchetype(arr: *std.ArrayList(@This()), entt: Entity) *Archetype {
            std.debug.assert(@This().valid(arr, entt));
            return arr.items[entt.index].arch;
        }

        pub inline fn getEntitySignature(arr: *std.ArrayList(@This()), entt: Entity) Components {
            return getEntityArchetype(arr, entt).signature;
        }
    };
}
