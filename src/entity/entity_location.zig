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
    };
}
