pub const ParameterData = struct {
    /// index in the system function itself
    global_index: usize,
    /// index per type (Query, EventReader, EventWriter, Resource)
    type_index: usize,
};
