const std = @import("std");

pub const TypeStoreOptions = struct {
    Resources: type,
};

pub fn TypeStore(comptime options: TypeStoreOptions) type {
    return struct {
        pub const Marker = TypeStore;
        pub const Resources = options.Resources;

        allocator: std.mem.Allocator,
        store: std.AutoHashMap(Resources.ResourceTypeId, *anyopaque),
        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .allocator = alloc,
                .store = .init(alloc),
            };
        }
        pub inline fn get(self: *@This(), comptime T: type) *T {
            return self.optGet(T).?;
        }
        pub inline fn getConst(self: *@This(), comptime T: type) *const T {
            return self.optGetConst(T).?;
        }
        pub inline fn optGet(self: *@This(), comptime T: type) ?*T {
            return @ptrCast(@alignCast(self.store.get(Resources.hash(T))));
        }
        pub inline fn optGetConst(self: *@This(), comptime T: type) ?*const T {
            return @ptrCast(@alignCast(self.store.get(Resources.hash(T))));
        }
        pub fn insert(self: *@This(), value: anytype) !void {
            const T = @TypeOf(value);
            const ptr: *T = try self.allocator.create(T);
            @memcpy(std.mem.asBytes(ptr), std.mem.asBytes(&value));
            try self.store.put(Resources.hash(T), ptr);
        }
        pub fn remove(self: *@This(), comptime T: type) void {
            if (comptime @hasDecl(T, "deinit")) {
                if (self.optGet(Resources.hash(T))) |ptr| {
                    ptr.deinit();
                }
            }
            self.store.remove(Resources.hash(T));
        }
        pub fn deinit(self: *@This()) void {
            comptime var iter = Resources.Iterator.init();
            inline while (comptime iter.nextType()) |Type| {
                switch (@typeInfo(Type)) {
                    .@"struct", .@"enum", .@"union", .@"opaque" => {
                        if (comptime @hasDecl(Type, "deinit")) {
                            if (self.optGet(Type)) |ptr| {
                                ptr.deinit();
                            }
                        }
                    },
                    else => {},
                }
                if (self.optGet(Type)) |ptr| {
                    self.allocator.destroy(ptr);
                }
            }
            self.store.deinit();
        }
        pub fn len(self: *@This()) usize {
            return self.store.count();
        }
    };
}

test TypeStore {
    const Resources = @import("resources.zig").Resources;
    var store = TypeStore(.{ .Resources = Resources(&.{ u64, u8, u32 }) }).init(std.testing.allocator);
    defer store.deinit();
    try store.insert(@as(u64, 8));
    try std.testing.expectEqual(1, store.len());
    try std.testing.expectEqual(@as(u64, 8), store.get(u64).*);
}
