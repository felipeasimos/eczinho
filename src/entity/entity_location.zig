pub const EntityLocationOptions = struct {
    Archetype: type,
};

pub fn EntityLocation(comptime options: EntityLocationOptions) type {
    return struct {
        pub const Archetype = options.Archetype;
        pub const Chunk = Archetype.DenseStorage.Chunk;
        pub const Components = Archetype.Components;
        pub const Entity = Archetype.Entity;

        // pointer to archetype. Contains entity's signature.
        // changes to the entity's signature change the archetype, but doesn't
        // move the underlying data if no changes to dense components were made
        arch: *Archetype,
        // points to chunk, if the entity currently resides in a chunked archetype
        chunk: *Chunk,
        // slot index inside the chunk if Chunks are used
        // table index if Tables are used
        dense_index: usize,
        // current (if alive) or next (if dead) generation of an entity index.
        version: Entity.Version = 0,
    };
}
