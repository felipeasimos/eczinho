pub const TableOptions = struct {
    Entity: type,
    EntityLocation: type,
    Components: type,
    GrowthRatio: usize,
    InitialNumElements: usize,
};

pub fn Tables(comptime options: TableOptions) type {
    _ = options;
    return struct {};
}
