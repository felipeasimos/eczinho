pub const QueryRequest = struct {
    /// required and optional components, will be accessible inside the system
    /// using `*Component` or `*const Component` will return a pointer to the value.
    /// using `Component` will return a copy of the value.
    /// using `?*Component`, `?*const Component` or `?Component` will return a pointer or copy if it exists for the entity
    /// using `?*Component` or `*Component` will mark the component as changed (see changed member below)
    q: []const type = &.{},
    /// additional components that the entity must NOT have.
    /// (but won't be returned).
    without: []const type = &.{},
    /// additional components that the entity must have.
    /// (but won't be returned).
    with: []const type = &.{},
    /// only return entities which had these components added since this system last run
    added: []const type = &.{},
    /// only return entities which had these components changed since this system last run
    changed: []const type = &.{},
};
