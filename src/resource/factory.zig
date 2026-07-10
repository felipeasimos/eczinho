pub const ResourceFactoryOptions = struct {
    TypeStore: type,
    T: type,
};

/// Really just a compilation guard that checks if the given type is properly registered as a Resource.
pub fn ResourceFactory(comptime options: ResourceFactoryOptions) type {
    const Resources = options.TypeStore.TypeHasher;
    if (comptime !Resources.isResource(options.T)) {
        const CanonicalType = Resources.getCanonicalType(options.T);
        if (comptime !Resources.isResource(CanonicalType)) {
            @compileError("type '" ++ @typeName(CanonicalType) ++ "' is not a registered Resource");
        }
    }
    return options.T;
}
