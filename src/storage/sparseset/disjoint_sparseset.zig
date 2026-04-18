const std = @import("std");

pub const ValueType = struct {
    name: []const u8,
    T: type,
};

pub const DisjointSparseSetOptions = struct {
    K: type,
    Vs: []const ValueType,
    PageSize: usize = 4096,
};

fn CreateValueTuple(comptime Vs: []const ValueType) type {
    var field_types: []const type = &.{};

    for (Vs) |V| {
        field_types = field_types ++ .{V.T};
    }

    return @Tuple(field_types);
}

fn CreateValueStruct(comptime Vs: []const ValueType) type {
    var field_names: []const []const u8 = &.{};
    // SAFETY: populated in the loop below
    var field_types: [Vs.len]type = undefined;
    // SAFETY: populated in the loop below
    var field_attrs: [Vs.len]std.builtin.Type.StructField.Attributes = undefined;

    for (Vs, 0..) |V, i| {
        field_names = field_names ++ .{V.name};
        field_types[i] = V.T;
        field_attrs[i] = std.builtin.Type.StructField.Attributes{};
    }

    return @Struct(.auto, null, field_names, &field_types, &field_attrs);
}

fn CreateValueArrays(comptime Vs: []const ValueType) type {
    var field_names: []const []const u8 = &.{};
    // SAFETY: populated in the following loop
    var field_types: [Vs.len]type = undefined;
    // SAFETY: populated in the following loop
    var field_attrs: [Vs.len]std.builtin.Type.StructField.Attributes = undefined;

    for (Vs, 0..) |V, i| {
        field_names = field_names ++ .{V.name};
        field_types[i] = std.ArrayList(V.T);
        field_attrs[i] = std.builtin.Type.StructField.Attributes{
            .default_value_ptr = &std.ArrayList(V.T).empty,
        };
    }

    return @Struct(.auto, null, field_names, &field_types, &field_attrs);
}

pub fn DisjointSparseSet(comptime options: DisjointSparseSetOptions) type {
    if (@popCount(options.PageSize) != 1) {
        @compileError("Page size is not a power of 2");
    }

    const key_bits = @typeInfo(options.K).int.bits;
    const usize_bits = @typeInfo(usize).int.bits;

    const KeyPage = struct {
        keys: []options.K,
    };

    return struct {
        pub const PageSize = options.PageSize;
        pub const PageMask = PageSize - 1;
        pub const K = options.K;
        pub const Vs = options.Vs;
        pub const empty: @This() = .{};
        pub const DisjointDataArrays = CreateValueArrays(Vs);
        pub const DisjointDataTuple = CreateValueTuple(Vs);
        pub const DisjointDataStruct = CreateValueStruct(Vs);
        pub const StorageAddress = struct { *@This(), K };

        const Null = std.math.maxInt(K);

        sparse: std.ArrayList(?KeyPage) = .empty,
        dense_keys: std.ArrayList(K) = .empty,
        dense_data: DisjointDataArrays = .{},

        pub fn init() @This() {
            return .{};
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.sparse.items) |page_opt| {
                if (page_opt) |p| {
                    allocator.free(p.keys);
                }
            }
            self.sparse.deinit(allocator);
            self.dense_keys.deinit(allocator);
            inline for (Vs) |V| {
                @field(self.dense_data, V.name).deinit(allocator);
            }
        }

        pub fn len(self: *@This()) usize {
            return self.dense_keys.items.len;
        }

        fn getDenseIndex(self: *@This(), key: K) usize {
            std.debug.assert(self.contains(key));
            return self.getPage(getPageIndex(key)).keys[getPageOffset(key)];
        }

        fn getPageIndex(key: K) usize {
            return (toUsize(key) & PageMask) / PageSize;
        }

        fn getPageOffset(key: K) usize {
            return toUsize(key) & (PageMask);
        }

        fn toUsize(key: K) usize {
            if (key_bits > usize_bits) {
                return @truncate(key);
            }
            return @intCast(key);
        }

        fn toKey(idx: usize) K {
            if (key_bits > usize_bits) {
                return @intCast(idx);
            }
            return @truncate(idx);
        }

        /// check if set already contains integer
        pub fn contains(self: *@This(), data: K) bool {
            std.debug.assert(data != Null);
            const p = getPageIndex(data);
            return p < self.sparse.items.len and
                self.sparse.items[p] != null and
                self.sparse.items[p].?.keys[getPageOffset(data)] != Null;
        }

        /// create page if it doesn't exists
        fn createPage(self: *@This(), allocator: std.mem.Allocator, page_index: usize) !void {
            if (page_index >= self.sparse.items.len) {
                const diff = page_index - self.sparse.items.len + 1;
                try self.sparse.appendNTimes(allocator, null, diff);
            }

            if (self.sparse.items[page_index] == null) {
                const new_page_data = try allocator.alloc(K, PageSize);
                @memset(new_page_data, Null);
                self.sparse.items[page_index] = KeyPage{
                    .keys = new_page_data,
                };
            }
        }

        /// get page
        inline fn getPage(self: *@This(), page_index: usize) *KeyPage {
            return &self.sparse.items[page_index].?;
        }

        fn checkValuesInput(T: type) void {
            if (T != DisjointDataTuple and T != DisjointDataStruct) {
                @compileError("input must be either " ++ @typeName(DisjointDataTuple) ++
                    " or " ++ @typeName(DisjointDataStruct));
            }
        }

        inline fn getInputField(
            values: anytype,
            comptime index: usize,
        ) @FieldType(DisjointDataTuple, std.fmt.comptimePrint("{}", .{index})) {
            if (@TypeOf(values) == DisjointDataTuple) {
                return values[index];
            } else if (@TypeOf(values) == DisjointDataStruct) {
                return @field(values, Vs[index].name);
            }
        }

        pub fn reserve(self: *@This(), allocator: std.mem.Allocator, key: K) !void {
            std.debug.assert(!self.contains(key));
            const page_index = getPageIndex(key);
            try self.createPage(allocator, page_index);
            const p = self.getPage(page_index);
            p.keys[getPageOffset(key)] = toKey(self.dense_keys.items.len);
            try self.dense_keys.append(allocator, key);

            inline for (Vs) |V| {
                // SAFETY: the whole idea of "reserve" is to just reserve space for data,
                // without actually setting it
                try @field(self.dense_data, V.name).append(allocator, undefined);
            }
        }

        pub fn addOne(
            self: *@This(),
            allocator: std.mem.Allocator,
            comptime Name: []const u8,
            key: K,
            value: @FieldType(DisjointDataStruct, Name),
        ) !void {
            std.debug.assert(!self.contains(key));
            const page_index = getPageIndex(key);
            try self.createPage(allocator, page_index);
            const p = self.getPage(page_index);
            p.keys[getPageOffset(key)] = toKey(self.dense_keys.items.len);
            try self.dense_keys.append(allocator, key);

            inline for (Vs) |V| {
                @field(self.dense_data, V.name).append(allocator, value);
            }
        }

        pub fn add(self: *@This(), allocator: std.mem.Allocator, key: K, disjoint_values: anytype) !void {
            comptime checkValuesInput(@TypeOf(disjoint_values));

            std.debug.assert(!self.contains(key));
            const page_index = getPageIndex(key);
            try self.createPage(allocator, page_index);
            const p = self.getPage(page_index);
            p.keys[getPageOffset(key)] = toKey(self.dense_keys.items.len);
            try self.dense_keys.append(allocator, key);

            inline for (Vs, 0..) |V, i| {
                const value = getInputField(disjoint_values, i);
                @field(self.dense_data, V.name).append(allocator, value);
            }
        }

        fn getElementSparsePtr(self: *@This(), data: K) *K {
            const p = self.getPage(getPageIndex(data));
            return &p.keys[getPageOffset(data)];
        }

        // remove integer from set. Nothing happens if integer is already not contained
        // return dense index
        pub fn remove(self: *@This(), data: K) usize {
            std.debug.assert(self.contains(data));

            const p = self.getPage(getPageIndex(data));
            const last_ptr = self.getElementSparsePtr(self.dense_keys.getLast());
            // 1. set 'data' in dense array to be the value of the last element in the dense array
            const dense_index = p.keys[getPageOffset(data)];
            last_ptr.* = dense_index;
            // 2. set 'data' in the sparse array to set to Null
            p.keys[getPageOffset(data)] = Null;

            _ = self.dense_keys.swapRemove(dense_index);
            inline for (Vs) |V| {
                _ = @field(self.dense_data, V.name).swapRemove(dense_index);
            }
            return dense_index;
        }

        pub inline fn get(self: *@This(), key: K, comptime Name: []const u8) *@FieldType(DisjointDataStruct, Name) {
            const dense_index = self.getDenseIndex(key);
            return &@field(self.dense_data, Name).items[dense_index];
        }

        pub inline fn getConst(self: *@This(), key: K, comptime Name: []const u8) @FieldType(DisjointDataStruct, Name) {
            const dense_index = self.getDenseIndex(key);
            return @field(self.dense_data, Name).items[dense_index];
        }

        pub fn keys(self: *@This()) []K {
            return self.dense_keys.items;
        }
    };
}

test "sparseset init" {
    var _u1 = DisjointSparseSet(.{ .T = u1 }).init(std.testing.allocator);
    try std.testing.expectEqual(0, _u1.len());
}

test "u2 sparseset contains" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try std.testing.expect(!_u2.contains(0));
    try std.testing.expect(!_u2.contains(1));
}

test "u2 sparseset add" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try std.testing.expect(_u2.contains(0));
    try std.testing.expectEqual(1, _u2.len());
}

test "u2 sparseset multiple add" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try _u2.add(1);
    try std.testing.expect(_u2.contains(1));
    try std.testing.expectEqual(2, _u2.len());
    try _u2.add(2);
    try std.testing.expect(_u2.contains(2));
    try std.testing.expectEqual(3, _u2.len());
}

test "u2 sparseset multiple add out of order" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try _u2.add(2);
    try std.testing.expect(_u2.contains(2));
    try std.testing.expectEqual(2, _u2.len());
    try _u2.add(1);
    try std.testing.expect(_u2.contains(1));
    try std.testing.expectEqual(3, _u2.len());
}

test "u2 sparseset multiple add redundant" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(0);
    try _u2.add(2);
    try std.testing.expect(_u2.contains(2));
    try std.testing.expectEqual(2, _u2.len());
    try _u2.add(1);
    try std.testing.expect(_u2.contains(1));
    try std.testing.expectEqual(3, _u2.len());
}

test "u2 sparseset remove" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(2);
    try _u2.add(0);
    try _u2.add(1);

    try std.testing.expectEqual(1, _u2.remove(0));
    try std.testing.expectEqual(2, _u2.len());
    try std.testing.expect(!_u2.contains(0));
    try std.testing.expect(_u2.contains(1));
    try std.testing.expect(_u2.contains(2));
}

test "u2 sparseset multiple remove" {
    var _u2 = DisjointSparseSet(.{ .T = u2 }).init(std.testing.allocator);
    defer _u2.deinit();

    try _u2.add(2);
    try _u2.add(0);
    try _u2.add(1);

    _ = _u2.remove(0);
    try std.testing.expectEqual(0, _u2.remove(2));
    try std.testing.expectEqual(1, _u2.len());
    try std.testing.expect(!_u2.contains(0));
    try std.testing.expect(_u2.contains(1));
    try std.testing.expect(!_u2.contains(2));
    try std.testing.expectEqual(0, _u2.remove(1));
    try std.testing.expectEqual(0, _u2.len());
}

test "u40 sparseset contains" {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try std.testing.expect(!_u40.contains(0));
    try std.testing.expect(!_u40.contains(1));
}

test "u40 sparseset add" {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try std.testing.expect(_u40.contains(0));
    try std.testing.expectEqual(1, _u40.len());
}

test "u40 sparseset multiple add" {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(1);
    try std.testing.expect(_u40.contains(1));
    try std.testing.expectEqual(2, _u40.len());
    try _u40.add(2);
    try std.testing.expect(_u40.contains(2));
    try std.testing.expectEqual(3, _u40.len());
}

test "u40 sparseset multiple add out of order" {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(2);
    try std.testing.expect(_u40.contains(2));
    try std.testing.expectEqual(2, _u40.len());
    try _u40.add(1);
    try std.testing.expect(_u40.contains(1));
    try std.testing.expectEqual(3, _u40.len());
}

test "u40 sparseset multiple add redundant" {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(2);
    try std.testing.expect(_u40.contains(2));
    try std.testing.expectEqual(2, _u40.len());
    try _u40.add(1);
    try std.testing.expect(_u40.contains(1));
    try std.testing.expectEqual(3, _u40.len());
}

test "u40 sparseset remove" {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(2);
    try _u40.add(0);
    try _u40.add(1);

    try std.testing.expectEqual(1, _u40.remove(0));
    try std.testing.expectEqual(2, _u40.len());
    try std.testing.expect(!_u40.contains(0));
    try std.testing.expect(_u40.contains(1));
    try std.testing.expect(_u40.contains(2));
}

test "u40 sparseset multiple remove" {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(2);
    try _u40.add(0);
    try _u40.add(1);

    _ = _u40.remove(0);
    try std.testing.expectEqual(0, _u40.remove(2));
    try std.testing.expectEqual(1, _u40.len());
    try std.testing.expect(!_u40.contains(0));
    try std.testing.expect(_u40.contains(1));
    try std.testing.expect(!_u40.contains(2));
    try std.testing.expectEqual(0, _u40.remove(1));
    try std.testing.expectEqual(0, _u40.len());
}

test DisjointSparseSet {
    var _u40 = DisjointSparseSet(.{ .T = u40 }).init(std.testing.allocator);
    defer _u40.deinit();

    try _u40.add(0);
    try _u40.add(32);
    try _u40.add(64);

    try std.testing.expectEqual(3, _u40.len());
    try std.testing.expect(_u40.contains(64));
    try std.testing.expect(_u40.contains(32));
    try std.testing.expect(_u40.contains(0));
}
