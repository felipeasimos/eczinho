const std = @import("std");
const Request = @import("request.zig").QueryRequest;
const ComponentsFactory = @import("../components.zig").Components;
const EntityFactory = @import("../entity.zig").EntityTypeFactory;
const archetype = @import("../archetype.zig");
const registry = @import("../registry.zig");

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
            for (req.q) |AccessibleType| {
                if (Entity == AccessibleType) continue;
                if (@typeInfo(AccessibleType) != .optional) {
                    const CanonicalType = Components.getCanonicalType(AccessibleType);
                    data = data ++ .{CanonicalType};
                }
            }
            for (req.with) |AccessibleType| {
                if (@typeInfo(AccessibleType) != .optional) {
                    const CanonicalType = Components.getCanonicalType(AccessibleType);
                    data = data ++ .{CanonicalType};
                }
            }
            break :MustHave data;
        };
        pub const CannotHave = CannotHave: {
            var data: []const type = &.{};
            for (req.without) |AccessibleType| {
                if (@typeInfo(AccessibleType) != .optional) {
                    const CanonicalType = Components.getCanonicalType(AccessibleType);
                    data = data ++ .{CanonicalType};
                }
            }
            break :CannotHave data;
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

        fn updateArchetypeSignatureList(self: *@This()) !std.ArrayList(Components) {
            const must_have = comptime Components.init(MustHave);
            const cannot_have = comptime Components.init(CannotHave);

            var key_iter = self.registry.archetypes.keyIterator();
            var arr: std.ArrayList(Components) = .empty;
            while (key_iter.next()) |key| {
                const sig = key.*;
                if (must_have.isSubsetOf(sig) and !cannot_have.hasIntersection(sig)) {
                    try arr.append(self.registry.allocator, key.*);
                }
            }
            return arr;
        }
        pub fn init(reg: *Registry) !@This() {
            var new: @This() = .{
                .registry = reg,
            };
            new.archetypes = try new.updateArchetypeSignatureList();
            return new;
        }
        pub fn deinit(self: *@This()) void {
            self.archetypes.deinit(self.registry.allocator);
        }
        pub fn iter(self: @This()) Iterator {
            return Iterator.init(self.registry, self.archetypes);
        }
        pub fn len(self: @This()) usize {
            var count: usize = 0;
            for (self.archetypes.items) |sig| {
                count += self.registry.getArchetypeFromSignature(sig).len();
            }
            return count;
        }
        pub fn empty(self: @This()) bool {
            for (self.archetypes.items) |sig| {
                var arch = self.registry.getArchetypeFromSignature(sig);
                if (arch.len() != 0) {
                    return false;
                }
            }
            return true;
        }
        pub fn peek(self: @This()) ?Tuple {
            for (self.archetypes.items) |sig| {
                var arch = self.registry.getArchetypeFromSignature(sig);
                if (arch.len() != 0) {
                    var inner_arch_iter = arch.iterator(req.q);
                    return inner_arch_iter.next().?;
                }
            }
            return null;
        }
        pub fn optSingle(self: @This()) ?Tuple {
            std.debug.assert(self.len() == 0 or self.len() == 1);
            if (self.len() == 1) {
                return self.single();
            }
            return null;
        }
        pub fn single(self: @This()) Tuple {
            std.debug.assert(self.len() == 1);
            for (self.archetypes.items) |sig| {
                var arch = self.registry.getArchetypeFromSignature(sig);
                if (arch.len() != 0) {
                    var inner_arch_iter = arch.iterator(req.q);
                    return inner_arch_iter.next().?;
                }
            }
            @panic("no tuple found");
        }

        pub const Iterator = struct {
            registry: *Registry,
            archetypes: std.ArrayList(Components),
            index: usize = 0,
            pub fn init(reg: *Registry, archs: std.ArrayList(Components)) @This() {
                return .{
                    .registry = reg,
                    .archetypes = archs,
                };
            }
            fn nextArchetype(self: *@This()) ?*Archetype {
                while (self.archetypes.getLastOrNull()) |sig| {
                    var arch = self.registry.getArchetypeFromSignature(sig);
                    if (self.index >= arch.len()) {
                        _ = self.archetypes.pop().?;
                        self.index = 0;
                        continue;
                    }
                    return arch;
                }
                return null;
            }
            pub fn next(self: *@This()) ?Tuple {
                if (self.nextArchetype()) |arch| {
                    var iterator = arch.iterator(req.q);
                    iterator.index = self.index;
                    const tuple = iterator.next().?;
                    self.index += 1;
                    return tuple;
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
