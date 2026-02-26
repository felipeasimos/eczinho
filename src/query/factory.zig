const std = @import("std");
const Request = @import("request.zig").QueryRequest;
const ComponentsFactory = @import("../components.zig").Components;
const EntityFactory = @import("../entity.zig").EntityTypeFactory;
const archetype = @import("../archetype.zig");
const registry = @import("../registry.zig");
const SystemData = @import("../system_data.zig").SystemData;
const Tick = @import("../types.zig").Tick;

pub const QueryFactoryOptions = struct {
    request: Request,
    Entity: type,
    Components: type,
};

/// use in systems to obtain a query. System signature should be like:
/// fn systemExample(q: Query(.{.q = &.{typeA, *typeB}, .with = &.{typeC}}) !void {
///     ...
/// }
/// checkout QueryRequest for more information
pub fn QueryFactory(comptime options: QueryFactoryOptions) type {
    const req = options.request;
    var fields: [req.q.len]std.builtin.Type.StructField = undefined;
    for (req.q, 0..) |AccessibleType, i| {
        if (comptime AccessibleType != options.Entity) {
            const T = options.Components.getCanonicalType(AccessibleType);
            options.Components.checkSize(T);
        }
        fields[i] = std.builtin.Type.StructField{
            .name = std.fmt.comptimePrint("{}", .{i}),
            .type = AccessibleType,
            .is_comptime = false,
            .default_value_ptr = null,
            .alignment = @alignOf(AccessibleType),
        };
    }
    const ResultTuple = @Type(std.builtin.Type{
        .@"struct" = .{
            .layout = .auto,
            .is_tuple = true,
            .fields = &fields,
            .decls = &.{},
        },
    });
    return struct {
        /// used to acknowledge that this type came from QueryFactory()
        pub const Marker = QueryFactory;
        pub const Entity = options.Entity;
        pub const Components = options.Components;
        pub const Tuple = ResultTuple;
        pub const request = options.request;
        pub const CanonicalTypes = CanonicalTypes: {
            var data: []const type = &.{};
            for (req.q) |AccessibleType| {
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
            for (req.q) |Type| {
                if (Entity == Type) continue;
                if (@typeInfo(Type) != .optional) {
                    const CanonicalType = Components.getCanonicalType(Type);
                    data = data ++ .{CanonicalType};
                }
            }
            data = data ++ req.with ++ req.added ++ req.changed;
            break :MustHave data;
        };
        pub const CannotHave = CannotHave: {
            break :CannotHave req.without;
        };
        pub const Registry = registry.Registry(.{
            .Entity = Entity,
            .Components = Components,
        });
        pub const Archetype = archetype.Archetype(.{
            .Entity = Entity,
            .Components = Components,
        });

        archetypes: std.ArrayList(Components) = .empty,
        registry: *Registry,
        system_data: *SystemData,

        inline fn checkSignature(sig: Components) bool {
            const must_have = comptime Components.init(MustHave);
            const cannot_have = comptime Components.init(CannotHave);
            return must_have.isSubsetOf(sig) and !cannot_have.hasIntersection(sig);
        }

        fn updateArchetypeSignatureList(self: *@This()) !std.ArrayList(Components) {
            var key_iter = self.registry.archetypes.keyIterator();
            var arr: std.ArrayList(Components) = .empty;
            while (key_iter.next()) |key| {
                const sig = key.*;
                if (checkSignature(sig)) {
                    try arr.append(self.registry.allocator, key.*);
                }
            }
            return arr;
        }
        pub fn init(reg: *Registry, system_data: *SystemData) !@This() {
            var new: @This() = .{
                .registry = reg,
                .system_data = system_data,
            };
            new.archetypes = try new.updateArchetypeSignatureList();
            return new;
        }
        pub fn deinit(self: *@This()) void {
            self.archetypes.deinit(self.registry.allocator);
        }
        pub fn iter(self: @This()) Iterator {
            return Iterator.init(self.registry, self.archetypes, self.system_data.last_run);
        }
        pub fn len(self: @This()) usize {
            var count: usize = 0;
            for (self.archetypes.items) |sig| {
                const arch = self.registry.getArchetypeFromSignature(sig);
                if (comptime req.added.len == 0 and req.changed.len == 0) {
                    count += arch.len();
                } else {
                    var arch_iter = arch.iterator(req.q, req.added, req.changed, self.system_data.last_run, self.registry.getTick());
                    while (arch_iter.nextWithoutMarkingChange()) |_| {
                        count += 1;
                    }
                }
            }
            return count;
        }
        pub fn empty(self: @This()) bool {
            for (self.archetypes.items) |sig| {
                var arch = self.registry.getArchetypeFromSignature(sig);
                if (comptime req.added.len == 0 and req.changed.len == 0) {
                    if (arch.len() != 0) return false;
                } else if (arch.len() != 0) {
                    var arch_iter = arch.iterator(req.q, req.added, req.changed, self.system_data.last_run, self.registry.getTick());
                    const arch_is_empty = arch_iter.nextWithoutMarkingChange() == null;
                    if (!arch_is_empty) return false;
                }
            }
            return true;
        }
        /// get next tuple, returning null if query is empty
        pub fn peek(self: @This()) ?Tuple {
            for (self.archetypes.items) |sig| {
                var arch = self.registry.getArchetypeFromSignature(sig);
                if (arch.len() != 0) {
                    var inner_arch_iter = arch.iterator(req.q, req.added, req.changed, self.system_data.last_run, self.registry.getTick());
                    return inner_arch_iter.next().?;
                }
            }
            return null;
        }
        /// get next tuple, panicking if there is more than one tuple in the query. Returns null if query is empty
        pub fn optSingle(self: @This()) ?Tuple {
            if (self.empty()) return null;
            var result: ?Tuple = null;
            for (self.archetypes.items) |sig| {
                var arch = self.registry.getArchetypeFromSignature(sig);
                if (arch.len() != 0) {
                    var inner_arch_iter = arch.iterator(req.q, req.added, req.changed, self.system_data.last_run, self.registry.getTick());
                    if (inner_arch_iter.next()) |tuple| {
                        if (result != null) @panic("optSingle found more than one valid tuple");
                        result = tuple;
                    }
                }
            }
            return result;
        }
        /// get next tuple, asserting that there is exactly one tuple in the query. Panics if query is empty.
        pub fn single(self: @This()) Tuple {
            std.debug.assert(!self.empty() and self.len() == 1);
            for (self.archetypes.items) |sig| {
                var arch = self.registry.getArchetypeFromSignature(sig);
                if (arch.len() != 0) {
                    var inner_arch_iter = arch.iterator(req.q, req.added, req.changed, self.system_data.last_run, self.registry.getTick());
                    return inner_arch_iter.next().?;
                }
            }
            @panic("no tuple found");
        }

        pub const Iterator = struct {
            registry: *Registry,
            archetypes: std.ArrayList(Components),
            last_system_run: Tick,
            current_iter: ?Archetype.Iterator(req.q, req.added, req.changed),
            pub fn init(reg: *Registry, archs: std.ArrayList(Components), last_system_run: Tick) @This() {
                var new: @This() = .{
                    .registry = reg,
                    .archetypes = archs,
                    .last_system_run = last_system_run,
                    .current_iter = null,
                };
                new.current_iter = new.nextArchetypeIterator();
                return new;
            }
            inline fn nextArchetypeIterator(self: *@This()) ?Archetype.Iterator(req.q, req.added, req.changed) {
                while (self.archetypes.pop()) |sig| {
                    const arch = self.registry.getArchetypeFromSignature(sig);
                    var iterator = arch.iterator(
                        req.q,
                        req.added,
                        req.changed,
                        self.last_system_run,
                        self.registry.getTick(),
                    );
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
                if (self.current_iter.?.next()) |tuple| {
                    return tuple;
                }
                // if nothing is returned from the current iter
                if (self.nextArchetypeIterator()) |iterator| {
                    self.current_iter = iterator;
                    return self.current_iter.?.next();
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
