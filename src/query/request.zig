pub const QueryRequest = struct {
    /// required and optional components, will be accessible inside the system
    /// using `*Component` or `*const Component` will return a pointer to the value.
    /// using `Component` will return a copy of the value.
    /// using `?*Component`, `?*const Component` or `?Component` will return a pointer or copy if it exists for the entity
    /// using `?*Component` or `*Component` will mark the component as changed (see changed member below)
    q: []const type = &.{},
    /// additional components that the entity must have.
    /// (but won't be returned).
    with: []const type = &.{},
    /// additional components that the entity must NOT have.
    /// (but won't be returned).
    without: []const type = &.{},
    /// only return entities which had these components added since this system last run
    added: []const type = &.{},
    /// only return entities which had these components changed since this system last run
    changed: []const type = &.{},

    pub fn isEmpty(self: @This()) bool {
        return self.q.len == 0 and
            self.with.len == 0 and
            self.without.len == 0 and
            self.added.len == 0 and
            self.changed.len == 0;
    }

    pub fn validate(self: @This(), comptime Components: type, comptime Entity: type) void {
        inline for (self.added) |Added| {
            if (!Components.hasAddedMetadata(Added)) {
                @compileError("Component " ++ @typeName(Added) ++ " is being queried for `added` metadata, " ++
                    "which it doesn't have. Please include it in the component config");
            }
        }
        inline for (self.changed) |Changed| {
            if (@sizeOf(Changed) == 0) {
                @compileError("zero size components types don't have Changed metadata");
            }
            if (!Components.hasChangedMetadata(Changed)) {
                @compileError("Component " ++ @typeName(Changed) ++ " is being queried for `changed` metadata, " ++
                    "which it doesn't have. Please include it in the component config");
            }
        }
        inline for (self.q) |AccessibleType| {
            if (comptime AccessibleType != Entity) {
                const CanonicalType = Components.getCanonicalType(AccessibleType);
                if (comptime @sizeOf(CanonicalType) == 0) {
                    @compileError("Can't return a zero-sized type ++ (" ++ @typeName(CanonicalType) ++
                        ") in query");
                }
            }
        }
    }
};
