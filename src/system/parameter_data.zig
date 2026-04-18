pub const ParameterData = struct {
    /// index in the system function itself
    global_index: usize,
    /// index per type (Query, EventReader, EventWriter, Resource)
    /// this is useful for EventReaders
    type_index: usize,
};
