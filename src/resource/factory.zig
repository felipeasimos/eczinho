pub const ResourceFactoryOptions = struct {
    TypeStore: type,
    T: type,
};

pub fn ResourceFactory(comptime options: ResourceFactoryOptions) type {
    return struct {
        pub const Marker = ResourceFactory;
        pub const TypeStore = options.TypeStore;
        pub const T = options.T;

        store: *TypeStore,
        pub fn init(store: *TypeStore) @This() {
            return .{
                .store = store,
            };
        }
        pub fn get(self: @This()) *T {
            return self.store.get(T);
        }
        pub fn getConst(self: @This()) *const T {
            return self.store.getConst(T);
        }
        pub fn deinit(self: @This()) void {
            _ = self;
        }
    };
}
