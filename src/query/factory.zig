const std = @import("std");
const Request = @import("request.zig").QueryRequest;
const ComponentsFactory = @import("../components.zig").Components;
const EntityFactory = @import("../entity/entity.zig").EntityTypeFactory;
const world = @import("../world.zig");
const SystemData = @import("../system_data.zig").SystemData;
const Tick = @import("../types.zig").Tick;

pub const QueryFactoryOptions = struct {
    request: Request,
    Entity: type,
    Components: type,
};

const QueryTypes = struct { dense: Request = .{}, sparse: Request = .{} };

/// use in systems to obtain a query. System signature should be like:
/// fn systemExample(q: Query(.{.q = &.{typeA, *typeB}, .with = &.{typeC}}) !void {
///     ...
/// }
/// checkout QueryRequest for more information
pub fn QueryFactory(comptime options: QueryFactoryOptions) type {
    options.request.validate(options.Components);
    const request = options.request;
    const req = req: {
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
        break :req req;
    };
    var field_types: [request.q.len]type = undefined;
    for (request.q, 0..) |AccessibleType, i| {
        if (comptime AccessibleType != options.Entity) {
            const T = options.Components.getCanonicalType(AccessibleType);
            options.Components.checkSize(T);
        }
        field_types[i] = AccessibleType;
    }
    const ResultTuple = @Tuple(&field_types);
    // check if all changed types are not zst
    for (request.changed) |Type| {
        if (@sizeOf(Type) == 0) {
            @compileError("zero size components types don't have Changed metadata");
        }
    }
    return struct {
        /// used to acknowledge that this type came from QueryFactory()
        pub const Marker = QueryFactory;
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const Tuple = ResultTuple;
        pub const CanonicalTypes = CanonicalTypes: {
            var data: []const type = &.{};
            for (request.q) |AccessibleType| {
                if (Entity == AccessibleType) continue;
                const CanonicalType = Components.getCanonicalType(AccessibleType);
                if (@sizeOf(CanonicalType) == 0) {
                    @compileError("Can't return a zero-sized type ++ (" ++ @typeName(CanonicalType) ++ ") in query");
                }
                options.Components.checkSize(CanonicalType);
                data = data ++ .{CanonicalType};
            }
            break :CanonicalTypes data;
        };
        pub const MustHave = MustHave: {
            var data: []const type = &.{};
            for (request.q) |Type| {
                if (Entity == Type) continue;
                if (@typeInfo(Type) != .optional) {
                    const CanonicalType = Components.getCanonicalType(Type);
                    data = data ++ .{CanonicalType};
                }
            }
            data = data ++ request.with ++ request.added ++ request.changed;
            break :MustHave data;
        };
        pub const CannotHave = CannotHave: {
            break :CannotHave request.without;
        };
        pub const World = world.World(.{
            .Entity = Entity,
            .Components = Components,
        });
        pub const Archetype = World.Archetype;

        archetypes: std.ArrayList(Components) = .empty,
        world: *World,
        system_data: *SystemData,

        inline fn checkSignature(sig: Components) bool {
            const must_have = comptime Components.init(MustHave);
            const cannot_have = comptime Components.init(CannotHave);
            return must_have.isSubsetOf(sig) and !cannot_have.hasIntersection(sig);
        }

        fn updateArchetypeSignatureList(self: *@This()) !std.ArrayList(Components) {
            var key_iter = self.world.archetypes.keyIterator();
            var arr: std.ArrayList(Components) = .empty;
            while (key_iter.next()) |key| {
                const sig = key.*;
                if (checkSignature(sig)) {
                    try arr.append(self.world.allocator, key.*);
                }
            }
            return arr;
        }
        pub fn init(reg: *World, system_data: *SystemData) !@This() {
            var new: @This() = .{
                .world = reg,
                .system_data = system_data,
            };
            new.archetypes = try new.updateArchetypeSignatureList();
            return new;
        }
        pub fn deinit(self: *@This()) void {
            self.archetypes.deinit(self.world.allocator);
        }
        pub fn iter(self: @This()) Iterator {
            return Iterator.init(self.world, self.archetypes, self.system_data.last_run);
        }
        inline fn archetypeIterator(self: @This(), arch: *Archetype) Archetype.Iterator(
            req.dense.q,
            req.dense.added,
            req.dense.changed,
        ) {
            return arch.iterator(
                req.dense.q,
                req.dense.added,
                req.dense.changed,
                self.system_data.last_run,
                self.world.getTick(),
            );
        }
        fn sparseEnttIsValid(self: @This(), entt: Entity) bool {
            inline for (req.sparse.added) |Added| {
                const added_tick = self.world.sparse_sets.getAddedConst(Added, entt);
                if (added_tick < self.system_data.last_run) return false;
            }
            inline for (req.sparse.changed) |Changed| {
                const changed_tick = self.world.sparse_sets.getChangedConst(Changed, entt);
                if (changed_tick < self.system_data.last_run) return false;
            }
            return true;
        }
        fn addToDenseTuple(self: @This(), entt: Entity, dense_tuple: @Tuple(req.dense.q), comptime mark_change: bool) Tuple {
            var tuple: Tuple = undefined;
            comptime var dense_counter = 0;
            comptime var tuple_counter = 0;
            inline for (request.q) |Q| {
                if (comptime Q == Entity) {
                    tuple[tuple_counter] = entt;
                    tuple_counter += 1;
                    continue;
                }
                const CanonicalType = Components.getCanonicalType(Q);
                switch (comptime Components.getStorageType(CanonicalType)) {
                    .Dense => {
                        tuple[tuple_counter] = dense_tuple[dense_counter];
                        dense_counter += 1;
                    },
                    .Sparse => {
                        const AccessType = comptime Components.getAccessType(Q);
                        const value: Q = switch (comptime AccessType) {
                            .Const => self.world.sparse_sets.getConst(CanonicalType, entt),
                            .PointerConst => @ptrCast(self.world.sparse_sets.get(CanonicalType, entt)),
                            .PointerMut => self.world.sparse_sets.get(CanonicalType, entt),
                            .OptionalConst => self.world.sparse_sets.getConst(CanonicalType, entt),
                            .OptionalPointerMut => self.world.sparse_sets.get(CanonicalType, entt),
                            .OptionalPointerConst => @ptrCast(self.world.sparse_sets.getConst(CanonicalType, entt)),
                        };
                        if (comptime (mark_change and Components.hasChangedMetadata(CanonicalType))) {
                            if (comptime (AccessType == .PointerMut)) {
                                self.world.sparse_sets.getChanged(CanonicalType, entt).* = self.world.getTick();
                            } else if (comptime (AccessType == .OptionalPointerMut)) {
                                if (value != null) {
                                    self.world.sparse_sets.getChanged(CanonicalType, entt).* = self.world.getTick();
                                }
                            }
                        }
                        tuple[tuple_counter] = value;
                    },
                }
                tuple_counter += 1;
            }
            return tuple;
        }
        pub fn len(self: @This()) usize {
            var count: usize = 0;
            for (self.archetypes.items) |sig| {
                const arch = self.world.getArchetypeFromSignature(sig);
                if (comptime request.added.len == 0 and request.changed.len == 0) {
                    count += arch.len();
                } else {
                    var arch_iter = self.archetypeIterator(arch);
                    while (arch_iter.nextWithoutMarkingChange()) |res| {
                        const entt, _ = res;
                        count += @intFromBool(self.sparseEnttIsValid(entt));
                    }
                }
            }
            return count;
        }
        pub fn empty(self: @This()) bool {
            for (self.archetypes.items) |sig| {
                var arch = self.world.getArchetypeFromSignature(sig);
                if (comptime request.added.len == 0 and request.changed.len == 0) {
                    if (arch.len() != 0) return false;
                } else if (arch.len() != 0) {
                    var arch_iter = self.archetypeIterator(arch);
                    const arch_is_empty = arch_iter.nextWithoutMarkingChange() == null;
                    if (!arch_is_empty) return false;
                }
            }
            return true;
        }
        /// get next tuple, returning null if query is empty
        pub fn peek(self: @This()) ?Tuple {
            for (self.archetypes.items) |sig| {
                const arch = self.world.getArchetypeFromSignature(sig);
                var inner_arch_iter = self.archetypeIterator(arch);
                while (inner_arch_iter.nextWithoutMarkingChange()) |res| {
                    const entt, const dense_tuple = res;
                    if (self.sparseEnttIsValid(entt)) {
                        return self.addToDenseTuple(entt, dense_tuple, false);
                    }
                }
            }
            return null;
        }
        /// get next tuple, panicking if there is more than one tuple in the query. Returns null if query is empty
        pub fn optSingle(self: @This()) ?Tuple {
            if (self.empty()) return null;
            var result: ?Tuple = null;
            for (self.archetypes.items) |sig| {
                var arch = self.world.getArchetypeFromSignature(sig);
                if (arch.len() != 0) {
                    var inner_arch_iter = self.archetypeIterator(arch);
                    while (inner_arch_iter.peek()) |res| {
                        if (result != null) @panic("optSingle found more than one valid tuple");
                        const entt, const dense_tuple = res;
                        if (self.sparseEnttIsValid(entt)) {
                            _ = inner_arch_iter.next();
                            result = self.addToDenseTuple(entt, dense_tuple, true);
                        } else {
                            _ = inner_arch_iter.nextWithoutMarkingChange();
                        }
                    }
                    if (inner_arch_iter.next() != null) {
                        @panic("optSingle found more than one valid tuple");
                    }
                }
            }
            return result;
        }
        /// get next tuple, asserting that there is exactly one tuple in the query. Panics if query is empty.
        pub fn single(self: @This()) Tuple {
            std.debug.assert(!self.empty() and self.len() == 1);
            for (self.archetypes.items) |sig| {
                var arch = self.world.getArchetypeFromSignature(sig);
                if (arch.len() != 0) {
                    var inner_arch_iter = self.archetypeIterator(arch);
                    while (inner_arch_iter.peek()) |res| {
                        const entt, const dense_tuple = res;
                        if (self.sparseEnttIsValid(entt)) {
                            _ = inner_arch_iter.next();
                            return self.addToDenseTuple(entt, dense_tuple, true);
                        } else {
                            _ = inner_arch_iter.nextWithoutMarkingChange();
                        }
                    }
                }
            }
            @panic("no tuple found");
        }

        pub const Iterator = struct {
            world: *World,
            archetypes: std.ArrayList(Components),
            last_system_run: Tick,
            current_iter: ?Archetype.Iterator(request.q, request.added, request.changed),
            pub fn init(reg: *World, archs: std.ArrayList(Components), last_system_run: Tick) @This() {
                var new: @This() = .{
                    .world = reg,
                    .archetypes = archs,
                    .last_system_run = last_system_run,
                    .current_iter = null,
                };
                new.current_iter = new.nextArchetypeIterator();
                return new;
            }
            inline fn archetypeIterator(self: @This(), arch: *Archetype) Archetype.Iterator(
                req.dense.q,
                req.dense.added,
                req.dense.changed,
            ) {
                return arch.iterator(
                    req.dense.q,
                    req.dense.added,
                    req.dense.changed,
                    self.last_system_run,
                    self.world.getTick(),
                );
            }

            inline fn nextArchetypeIterator(self: *@This()) ?Archetype.Iterator(request.q, request.added, request.changed) {
                while (self.archetypes.pop()) |sig| {
                    const arch = self.world.getArchetypeFromSignature(sig);
                    var iterator = self.archetypeIterator(arch);
                    if (iterator.peek()) |_| {
                        return iterator;
                    }
                }
                return null;
            }
            pub fn next(self: *@This()) ?Tuple {
                if (self.current_iter == null) {
                    return null;
                }
                if (self.current_iter.?.next()) |iter_result| {
                    _, const tuple = iter_result;
                    return tuple;
                }
                // if nothing is returned from the current iter
                if (self.nextArchetypeIterator()) |iterator| {
                    self.current_iter = iterator;
                    if (self.current_iter.?.next()) |iter_result| {
                        _, const tuple = iter_result;
                        return tuple;
                    }
                    return null;
                }
                return null;
            }
        };
    };
}

test QueryFactory {
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
        .Entity = EntityFactory(.medium),
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
