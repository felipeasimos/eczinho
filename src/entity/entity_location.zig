pub const EntityLocationOptions = struct {
    Archetype: type,
};

pub fn EntityLocation(comptime options: EntityLocationOptions) type {
    return struct {
        pub const Archetype = options.Archetype;
        pub const Components = Archetype.Components;
        pub const Entity = Archetype.Entity;

        /// pointer to archetype. Contains entity's signature.
        /// changes to the entity's signature change the archetype, but doesn't
        /// move the underlying data if no changes to dense components were made
        arch: *Archetype,
        /// points to a more specific storage unit to work with
        /// this only really matters when dealing with chunks (so you get a pointer to a single chunk)
        /// in the case of tables you will get the entire tables storage.
        /// anyways, it is important to keep everything consistent between chunks and tables
        /// (also, we would need it for efficient chunking anyway, so it's like there is a problem to
        /// use it for tables also, even though it is slightly redundant)
        storage: *Archetype.DenseStorage.Storage,
        // slot index inside the chunk if Chunks are used
        // table index if Tables are used
        dense_index: usize,
        // current (if alive) or next (if dead) generation of an entity index.
        version: Entity.Version = 0,
    };
}
