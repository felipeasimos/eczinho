const std = @import("std");
const Request = @import("request.zig").QueryRequest;
const ComponentsFactory = @import("../components.zig").Components;
const SystemData = @import("../system/system_data.zig").SystemData;
const Tick = @import("../types.zig").Tick;
const Mut = @import("mut.zig").Mut;

pub const QueryFactoryOptions = struct {
    request: Request,
    Entity: type,
    Components: type,
    World: type,
};

const QueryTypes = struct {
    dense: Request = .{},
    sparse: Request = .{},
};

/// divide request between sparse and dense components
/// Entity type is kept at the dense part
fn divideRequest(comptime options: QueryFactoryOptions) QueryTypes {
    var req: QueryTypes = .{};
    for (@typeInfo(Request).@"struct".fields) |Field| {
        for (@field(options.request, Field.name)) |Type| {
            if (Type == options.Entity) {
                @field(req.dense, Field.name) = @field(req.dense, Field.name) ++ .{Type};
                continue;
            }
            const CanonicalType = options.Components.getCanonicalType(Type);
            const config = options.Components.getConfig(CanonicalType);
            switch (config.storage_type) {
                .Dense => @field(req.dense, Field.name) = @field(req.dense, Field.name) ++ .{Type},
                .Sparse => @field(req.sparse, Field.name) = @field(req.sparse, Field.name) ++ .{Type},
            }
        }
    }
    return req;
}

const InnerQueryOptions = struct {
    Options: QueryFactoryOptions,
    MustHave: []const type,
    CannotHave: []const type,
    DividedRequest: QueryTypes,
};

inline fn hasValidTicksGeneral(
    entt: anytype,
    dense_storage_address: anytype,
    sparse_sets: anytype,
    last_run: Tick,
    comptime Added: []const type,
    comptime Changed: []const type,
    comptime Components: type,
) bool {
    inline for (Added) |Type| {
        const added_tick = switch (comptime Components.getStorageType(Type)) {
            .Dense => dense_storage_address[0].getAddedArray(Type)[dense_storage_address[1]],
            .Sparse => sparse_sets.getAddedConst(Type, entt),
        };
        if (added_tick.lessThan(last_run)) return false;
    }
    inline for (Changed) |Type| {
        const changed_tick = switch (comptime Components.getStorageType(Type)) {
            .Dense => dense_storage_address[0].getChangedArray(Type)[dense_storage_address[1]],
            .Sparse => sparse_sets.getChangedConst(Type, entt),
        };
        if (changed_tick.lessThan(last_run)) return false;
    }
    return true;
}

inline fn GetComponentStorage(comptime World: type, comptime Component: type) type {
    return switch (comptime World.Components.getStorageType(Component)) {
        .Dense => World.DenseStorage,
        .Sparse => World.SparseSets,
    };
}

inline fn GetComponentMut(comptime World: type, comptime Component: type) type {
    return Mut(.{
        .T = Component,
        .Components = World.Components,
        .Storage = GetComponentStorage(World, Component),
    });
}

inline fn getComponent(
    comptime ResultType: type,
    world: anytype,
    storage: anytype,
    index: anytype,
    entt: anytype,
) WrappedType(@TypeOf(world.*), ResultType) {
    // if true, index is entt
    const World = @TypeOf(world.*);
    const Components = World.Components;
    const CanonicalType = comptime Components.getCanonicalType(ResultType);
    const MutType = GetComponentMut(World, CanonicalType);
    const AccessType = comptime Components.getAccessType(ResultType);
    return switch (comptime AccessType) {
        .Const => storage.getConst(CanonicalType, index),
        .PointerConst => @ptrCast(storage.get(CanonicalType, index)),
        .PointerMut => MutType.init(.{ storage, index }, world.getTick()),
        .OptionalConst => if (storage.contains(CanonicalType, entt, index))
            storage.getConst(CanonicalType, index)
        else
            null,
        .OptionalPointerMut => if (storage.contains(CanonicalType, entt, index))
            MutType.init(.{ storage, index }, world.getTick())
        else
            null,
        .OptionalPointerConst => if (storage.contains(CanonicalType, entt, index))
            @ptrCast(storage.get(CanonicalType, index))
        else
            null,
    };
}

inline fn WrappedType(comptime World: type, comptime Component: type) type {
    const Components = World.Components;
    const CanonicalType = Components.getCanonicalType(Component);
    const MutType = GetComponentMut(World, CanonicalType);
    return switch (Components.getAccessType(Component)) {
        .PointerMut => MutType,
        .OptionalPointerMut => ?MutType,
        inline else => Component,
    };
}

inline fn GetResultTupleType(comptime ResultTypes: []const type, comptime World: type) type {
    var types: []const type = &.{};
    for (ResultTypes) |Type| {
        if (Type == World.Entity) {
            types = types ++ .{World.Entity};
            continue;
        }
        const ResultType = WrappedType(World, Type);
        types = types ++ .{ResultType};
    }
    return @Tuple(types);
}

inline fn getResultTupleGeneral(
    world: anytype,
    entt: anytype,
    dense_storage_address: anytype,
    comptime ResultTypes: []const type,
    comptime ResultTuple: type,
) ResultTuple {
    const Entity = @TypeOf(entt);
    const Components = @TypeOf(world.*).Components;

    const dense_storage, const dense_index = dense_storage_address;
    // SAFETY: filled immediatly after
    var tuple: ResultTuple = undefined;
    inline for (ResultTypes, 0..) |Type, i| {
        if (comptime Type == Entity) {
            tuple[i] = entt;
        } else {
            const CanonicalType = comptime Components.getCanonicalType(Type);
            const StorageType = comptime Components.getStorageType(CanonicalType);
            tuple[i] = switch (comptime StorageType) {
                .Dense => getComponent(Type, world, dense_storage, dense_index, entt),
                .Sparse => getComponent(Type, world, &world.sparse_sets, entt, entt),
            };
        }
    }
    return tuple;
}

fn SparseQueryFactory(comptime mark: anytype, comptime options: InnerQueryOptions) type {
    const Components = options.Options.Components;
    const Entity = options.Options.Entity;
    const World = options.Options.World;
    const MustHave = options.MustHave;
    const CannotHave = options.CannotHave;
    const ResultTypes = options.Options.request.q;
    const request = options.Options.request;
    const ResultTupleType = GetResultTupleType(ResultTypes, World);
    const DenseStorage = World.DenseStorage;

    return struct {
        pub const Marker = mark;
        const Query = @This();
        archetypes: std.ArrayList(Components),
        world: *World,
        system_data: *SystemData,
        pub fn init(w: *World, system_data: *SystemData) !@This() {
            return .{
                .world = w,
                .system_data = system_data,
                .archetypes = try w.archetype_store.createArchetypeSignatureList(
                    w.allocator,
                    comptime MustHave,
                    comptime CannotHave,
                ),
            };
        }
        pub fn deinit(self: *@This()) void {
            self.archetypes.deinit(self.world.allocator);
        }
        pub inline fn hasValidTicks(self: *const @This(), entt: Entity, dense_storage_address: anytype) bool {
            return hasValidTicksGeneral(
                entt,
                dense_storage_address,
                &self.world.sparse_sets,
                self.system_data.last_run,
                request.added,
                request.changed,
                Components,
            );
        }
        pub inline fn getResultTuple(
            self: *const @This(),
            entt: anytype,
            dense_storage_address: anytype,
        ) ResultTupleType {
            return getResultTupleGeneral(
                self.world,
                entt,
                dense_storage_address,
                ResultTypes,
                ResultTupleType,
            );
        }
        /// get number of entities in query
        pub fn len(self: @This()) usize {
            var count: usize = 0;
            for (self.archetypes.items) |sig| {
                const arch = self.world.archetype_store.getArchetypeFromSignature(sig);
                if (comptime request.added.len == 0 and request.changed.len == 0) {
                    count += arch.len();
                } else {
                    var arch_iter = @TypeOf(arch.*).Iterator.init(arch);
                    while (arch_iter.next()) |entt| {
                        const dense_storage_address = self.world.getDenseStorageAddress(entt);
                        if (self.hasValidTicks(entt, dense_storage_address)) {
                            count += 1;
                        }
                    }
                }
            }
            return count;
        }
        pub fn empty(self: @This()) bool {
            for (self.archetypes.items) |sig| {
                const arch = self.world.archetype_store.getArchetypeFromSignature(sig);
                if (comptime request.added.len == 0 and request.changed.len == 0) {
                    if (arch.len() != 0) return false;
                } else if (arch.len() != 0) {
                    var arch_iter = @TypeOf(arch.*).Iterator.init(arch);
                    while (arch_iter.next()) |entt| {
                        const dense_storage_address = self.world.getDenseStorageAddress(entt);
                        if (self.hasValidTicks(entt, dense_storage_address)) {
                            return false;
                        }
                    }
                }
            }
            return true;
        }
        pub fn peek(self: @This()) ?ResultTupleType {
            for (self.archetypes.items) |sig| {
                const arch = self.world.archetype_store.getArchetypeFromSignature(sig);
                var arch_iter = @TypeOf(arch.*).Iterator.init(arch);
                while (arch_iter.next()) |entt| {
                    const dense_storage_address = self.world.getDenseStorageAddress(entt);
                    if (self.hasValidTicks(entt, dense_storage_address)) {
                        return self.getResultTuple(entt, dense_storage_address);
                    }
                }
            }
            return null;
        }
        /// get next tuple, panicking if there is more than one tuple in the query. Returns null if query is empty
        pub fn optSingle(self: @This()) ?ResultTupleType {
            if (self.empty()) return null;
            var result: ?ResultTupleType = null;
            for (self.archetypes.items) |sig| {
                const arch = self.world.archetype_store.getArchetypeFromSignature(sig);
                if (arch.len() == 0) continue;
                var arch_iter = @TypeOf(arch.*).Iterator.init(arch);
                while (arch_iter.next()) |entt| {
                    const dense_storage_address = self.world.getDenseStorageAddress(entt);
                    if (self.hasValidTicks(entt, dense_storage_address)) {
                        if (result != null) @panic("optSingle() found more than one valid tuple");
                        result = self.getResultTuple(entt, dense_storage_address);
                    }
                }
            }
            return result;
        }
        /// get next tuple, asserting that there is exactly one tuple in the query. Panics if query is empty.
        pub fn single(self: @This()) ResultTupleType {
            std.debug.assert(!self.empty());
            std.debug.assert(self.len() == 1);
            for (self.archetypes.items) |sig| {
                const arch = self.world.archetype_store.getArchetypeFromSignature(sig);
                if (arch.len() == 0) continue;
                var arch_iter = @TypeOf(arch.*).Iterator.init(arch);
                while (arch_iter.next()) |entt| {
                    const dense_storage_address = self.world.getDenseStorageAddress(entt);
                    if (self.hasValidTicks(entt, dense_storage_address)) {
                        return self.getResultTuple(entt, dense_storage_address);
                    }
                }
            }
            @panic("single() found no valid tuple");
        }

        pub fn iter(self: *const @This()) Iterator {
            return Iterator.init(self, self.archetypes.items, self.system_data.last_run);
        }

        pub const Iterator = struct {
            query: *const Query,
            archetypes: []Components,
            last_system_run: Tick,
            archetype_iter: ?DenseStorage.Iterator = null,
            pub fn init(query: *const Query, archetypes: []Components, last_system_run: Tick) @This() {
                var new = @This(){
                    .query = query,
                    .archetypes = archetypes,
                    .last_system_run = last_system_run,
                };
                if (archetypes.len == 0) return new;
                const archetype = query.world.storage_store.getStorageFromSignature(archetypes[0]);
                new.archetype_iter = @TypeOf(archetype.*).Iterator.init(archetype);
                new.archetypes = archetypes[1..];
                return new;
            }
            pub fn next(self: *@This()) ?ResultTupleType {
                if (self.archetype_iter) |_| {
                    while (self.archetype_iter.?.next()) |entt| {
                        const dense_storage_address = self.world.getDenseStorageAddress(entt);
                        if (self.query.hasValidTicks(entt, dense_storage_address)) {
                            return self.query.getResultTuple(entt, dense_storage_address);
                        }
                    }
                    if (self.archetypes.len == 0) {
                        self.archetype_iter = null;
                        return null;
                    }
                    const archetype = self.query.world.archetype_store.getArchetypeFromSignature(self.archetypes[0]);
                    self.archetype_iter = @TypeOf(archetype.*).Iterator.init(archetype);
                    self.archetypes = self.archetypes[1..];
                    return self.next();
                }
                return null;
            }
        };
    };
}

fn DenseQueryFactory(comptime mark: anytype, comptime options: InnerQueryOptions) type {
    const Components = options.Options.Components;
    const Entity = options.Options.Entity;
    const World = options.Options.World;
    const MustHave = options.MustHave;
    const CannotHave = options.CannotHave;
    const ResultTypes = options.Options.request.q;
    const request = options.Options.request;
    const ResultTupleType = GetResultTupleType(ResultTypes, World);
    const DenseStorage = World.DenseStorage;

    return struct {
        pub const Marker = mark;
        const Query = @This();
        storages: std.ArrayList(Components),
        world: *World,
        system_data: *SystemData,
        pub fn init(w: *World, system_data: *SystemData) !@This() {
            return .{
                .world = w,
                .system_data = system_data,
                .storages = try w.storage_store.createStorageSignatureList(
                    w.allocator,
                    comptime MustHave,
                    comptime CannotHave,
                ),
            };
        }
        pub fn deinit(self: *@This()) void {
            self.storages.deinit(self.world.allocator);
        }
        inline fn hasValidTicks(self: *const @This(), dense_storage_address: anytype) bool {
            return hasValidTicksGeneral(
                void, // will not be used for dense query
                dense_storage_address,
                void, // will not be used for dense query
                self.system_data.last_run,
                request.added,
                request.changed,
                Components,
            );
        }
        pub inline fn getResultTuple(
            self: *const @This(),
            entt: anytype,
            dense_storage_address: anytype,
        ) ResultTupleType {
            return getResultTupleGeneral(
                self.world,
                entt,
                dense_storage_address,
                ResultTypes,
                ResultTupleType,
            );
        }
        /// get number of entities in query
        pub fn len(self: @This()) usize {
            var count: usize = 0;
            for (self.storages.items) |sig| {
                const stor = self.world.storage_store.getStorageFromSignature(sig);
                if (comptime request.added.len == 0 and request.changed.len == 0) {
                    count += stor.len();
                } else {
                    var stor_iter = @TypeOf(stor.*).Iterator.init(stor);
                    while (stor_iter.next()) |dense_storage_address| {
                        if (self.hasValidTicks(dense_storage_address)) {
                            count += 1;
                        }
                    }
                }
            }
            return count;
        }
        pub fn empty(self: @This()) bool {
            for (self.storages.items) |sig| {
                const stor = self.world.storage_store.getStorageFromSignature(sig);
                if (comptime request.added.len == 0 and request.changed.len == 0) {
                    if (stor.len() != 0) return false;
                } else if (stor.len() != 0) {
                    var stor_iter = @TypeOf(stor.*).Iterator.init(stor);
                    while (stor_iter.next()) |dense_storage_address| {
                        if (self.hasValidTicks(dense_storage_address)) {
                            return false;
                        }
                    }
                }
            }
            return true;
        }
        pub fn peek(self: @This()) ?ResultTupleType {
            for (self.storages.items) |sig| {
                const stor = self.world.storage_store.getStorageFromSignature(sig);
                var stor_iter = @TypeOf(stor.*).Iterator.init(stor);
                while (stor_iter.next()) |dense_storage_address| {
                    if (self.hasValidTicks(dense_storage_address)) {
                        const dense_storage, const dense_index = dense_storage_address;
                        const entt = dense_storage.getConst(Entity, dense_index);
                        return self.getResultTuple(entt, dense_storage_address);
                    }
                }
            }
            return null;
        }
        /// get next tuple, panicking if there is more than one tuple in the query. Returns null if query is empty
        pub fn optSingle(self: @This()) ?ResultTupleType {
            if (self.empty()) return null;
            var result: ?ResultTupleType = null;
            for (self.storages.items) |sig| {
                const stor = self.world.storage_store.getStorageFromSignature(sig);
                if (stor.len() == 0) continue;
                var stor_iter = @TypeOf(stor.*).Iterator.init(stor);
                while (stor_iter.next()) |dense_storage_address| {
                    if (self.hasValidTicks(dense_storage_address)) {
                        if (result != null) @panic("optSingle() found more than one valid tuple");
                        const dense_storage, const dense_index = dense_storage_address;
                        const entt = dense_storage.getConst(Entity, dense_index);
                        result = self.getResultTuple(entt, dense_storage_address);
                    }
                }
            }
            return result;
        }
        /// get next tuple, asserting that there is exactly one tuple in the query. Panics if query is empty.
        pub fn single(self: @This()) ResultTupleType {
            std.debug.assert(!self.empty());
            std.debug.assert(self.len() == 1);
            for (self.storages.items) |sig| {
                const stor = self.world.storage_store.getStorageFromSignature(sig);
                if (stor.len() == 0) continue;
                var stor_iter = @TypeOf(stor.*).Iterator.init(stor);
                while (stor_iter.next()) |dense_storage_address| {
                    if (self.hasValidTicks(dense_storage_address)) {
                        const dense_storage, const dense_index = dense_storage_address;
                        const entt = dense_storage.getConst(Entity, dense_index);
                        return self.getResultTuple(entt, dense_storage_address);
                    }
                }
            }
            @panic("single() found no valid tuple");
        }

        pub fn iter(self: *const @This()) Iterator {
            return Iterator.init(self, self.storages.items, self.system_data.last_run);
        }

        pub const Iterator = struct {
            query: *const Query,
            storages: []Components,
            last_system_run: Tick,
            storage_iter: ?DenseStorage.Iterator = null,
            pub fn init(query: *const Query, storages: []Components, last_system_run: Tick) @This() {
                var new = @This(){
                    .query = query,
                    .storages = storages,
                    .last_system_run = last_system_run,
                };
                if (storages.len == 0) return new;
                const storage = query.world.storage_store.getStorageFromSignature(storages[0]);
                new.storage_iter = DenseStorage.Iterator.init(storage);
                new.storages = storages[1..];
                return new;
            }
            pub fn next(self: *@This()) ?ResultTupleType {
                if (self.storage_iter) |_| {
                    while (self.storage_iter.?.next()) |dense_storage_address| {
                        if (self.query.hasValidTicks(dense_storage_address)) {
                            const dense_storage, const dense_index = dense_storage_address;
                            const entt = dense_storage.getConst(Entity, dense_index);
                            return self.query.getResultTuple(entt, dense_storage_address);
                        }
                    }
                    if (self.storages.len == 0) {
                        self.storage_iter = null;
                        return null;
                    }
                    const storage = self.query.world.storage_store.getStorageFromSignature(self.storages[0]);
                    self.storage_iter = DenseStorage.Iterator.init(storage);
                    self.storages = self.storages[1..];
                    return self.next();
                }
                return null;
            }
        };
    };
}

/// use in systems to obtain a query. System signature should be like:
/// fn systemExample(q: Query(.{.q = &.{typeA, *typeB}, .with = &.{typeC}}) !void {
///     ...
/// }
/// checkout QueryRequest for more information
pub fn QueryFactory(comptime options: QueryFactoryOptions) type {
    options.request.validate(options.Components, options.Entity);
    const request = options.request;

    const divided_request = divideRequest(options);

    const is_only_dense = divided_request.sparse.isEmpty();

    const Entity = options.Entity;
    const Components = options.Components;

    const MustHave = MustHave: {
        var data: []const type = &.{};
        for (request.q) |Q| {
            if (Entity == Q) continue;
            const CanonicalType = Components.getCanonicalType(Q);
            if (@typeInfo(Q) != .optional) {
                data = data ++ .{CanonicalType};
            }
        }
        break :MustHave data ++
            request.with ++
            request.added ++
            request.changed;
    };

    const HasOptionals = HasOptionas: {
        for (request.q) |Q| {
            if (Entity == Q) continue;
            if (@typeInfo(Q) == .optional) {
                break :HasOptionas true;
            }
        }
        break :HasOptionas false;
    };

    const CannotHave = CannotHave: {
        break :CannotHave request.without;
    };

    const Marker = QueryFactory;

    const inner_query_options: InnerQueryOptions = .{
        .Options = options,
        .MustHave = MustHave,
        .CannotHave = CannotHave,
        .DividedRequest = divided_request,
    };

    return if (!is_only_dense or HasOptionals)
        SparseQueryFactory(Marker, inner_query_options)
    else
        DenseQueryFactory(Marker, inner_query_options);
}

test QueryFactory {
    const entity = @import("../entity/entity.zig");
    const camelCase1 = u31;
    const camelCase2 = u32;
    const camelCase3 = u33;
    const camelCase4 = u34;
    const camelCase5 = u35;
    const PascalCase1 = u36;
    const PascalCase2 = u37;
    const PascalCase3 = u38;
    const PascalCase4 = u39;
    const PascalCase5 = u40;
    const Query = QueryFactory(.{
        .request = .{
            .q = &.{
                camelCase1,
                *camelCase2,
                ?*camelCase3,
                *const camelCase4,
                ?*const camelCase5,
                PascalCase1,
                *PascalCase2,
                ?*PascalCase3,
                *const PascalCase4,
                ?*const PascalCase5,
            },
            .with = &.{ u32, f32 },
            .without = &.{u41},
        },
        .Components = ComponentsFactory(&.{
            camelCase1,
            camelCase2,
            camelCase3,
            camelCase4,
            camelCase5,
            PascalCase1,
            PascalCase2,
            PascalCase3,
            PascalCase4,
            PascalCase5,
        }),
        .Entity = entity.EntityFactory(.medium),
    });
    try std.testing.expectEqual(u31, @FieldType(Query.Tuple, "0"));
    try std.testing.expectEqual(*u32, @FieldType(Query.Tuple, "1"));
    try std.testing.expectEqual(?*u33, @FieldType(Query.Tuple, "2"));
    try std.testing.expectEqual(*const u34, @FieldType(Query.Tuple, "3"));
    try std.testing.expectEqual(?*const u35, @FieldType(Query.Tuple, "4"));

    try std.testing.expectEqual(u36, @FieldType(Query.Tuple, "5"));
    try std.testing.expectEqual(*u37, @FieldType(Query.Tuple, "6"));
    try std.testing.expectEqual(?*u38, @FieldType(Query.Tuple, "7"));
    try std.testing.expectEqual(*const u39, @FieldType(Query.Tuple, "8"));
    try std.testing.expectEqual(?*const u40, @FieldType(Query.Tuple, "9"));
}
