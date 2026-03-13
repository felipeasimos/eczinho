const std = @import("std");

pub const TypeStoreOptions = struct {
    TypeHasher: type,
};

fn initTupleType(comptime TypeHasher: type) type {
    var field_types: [TypeHasher.Len]type = undefined;
    var iter = comptime TypeHasher.Iterator.init();
    var i = 0;
    inline while (iter.nextType()) |Type| {
        field_types[i] = ?Type;
        i += 1;
    }
    return @Tuple(&field_types);
}

pub fn TypeStore(comptime options: TypeStoreOptions) type {
    return struct {
        pub const Marker = TypeStore;
        pub const TypeHasher = options.TypeHasher;

        pub const TypesTuple = initTupleType(TypeHasher);

        values: TypesTuple,

        pub fn init() @This() {
            comptime var iter = TypeHasher.Iterator.init();
            comptime var i = 0;
            // SAFETY: immediatly filled in the following lines
            var values: TypesTuple = undefined;
            inline while (iter.nextType()) |_| {
                values[i] = null;
                i += 1;
            }
            return .{
                .values = values,
            };
        }
        pub inline fn clone(self: *@This(), comptime T: type) T {
            return self.optGetConst(T).?.*;
        }
        pub inline fn get(self: *@This(), comptime T: type) *T {
            return self.optGet(T).?;
        }
        pub inline fn getConst(self: *@This(), comptime T: type) *const T {
            return self.optGetConst(T).?;
        }
        pub inline fn optGet(self: *@This(), comptime T: type) ?*T {
            if (self.values[comptime TypeHasher.getIndex(T)]) |*value| {
                return value;
            }
            return null;
        }
        pub inline fn optGetConst(self: *@This(), comptime T: type) ?*const T {
            if (self.values[comptime TypeHasher.getIndex(T)]) |*value| {
                return value;
            }
            return null;
        }
        pub fn insert(self: *@This(), value: anytype) void {
            self.values[comptime TypeHasher.getIndex(@TypeOf(value))] = value;
        }
        pub fn remove(self: *@This(), comptime T: type) void {
            self.get(T).* = null;
        }
        pub fn deinit(self: *@This()) void {
            comptime var iter = TypeHasher.Iterator.init();
            inline while (comptime iter.nextType()) |Type| {
                switch (@typeInfo(Type)) {
                    .@"struct", .@"enum", .@"union", .@"opaque" => {
                        if (comptime @hasDecl(Type, "deinit")) {
                            if (self.optGet(Type)) |val| {
                                val.deinit();
                            }
                        }
                    },
                    else => {},
                }
            }
        }
        pub fn len(self: *@This()) usize {
            comptime var iter = TypeHasher.Iterator.init();
            var i: usize = 0;
            inline while (iter.nextType()) |Type| {
                if (self.optGet(Type) != null) {
                    i += 1;
                }
            }
            return i;
        }
    };
}

test TypeStore {
    const Resources = @import("resources.zig").Resources;
    var store = TypeStore(.{ .TypeHasher = Resources(&.{ u64, u8, u32 }) }).init();
    defer store.deinit();
    store.insert(@as(u64, 8));
    try std.testing.expectEqual(1, store.len());
    try std.testing.expectEqual(@as(u64, 8), store.get(u64).*);
}
