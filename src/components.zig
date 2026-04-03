// zlint-disable case-convention
const std = @import("std");
const TypeHasher = @import("type_hasher.zig").TypeHasher;
const StorageType = @import("storage/storage_types.zig").StorageType;

pub const ComponentMetadata = enum {
    Added,
    Changed,
};

pub const ComponentConfig = struct {
    storage_type: StorageType = .Dense,
    track_metadata: struct {
        added: bool = false,
        changed: bool = false,
        removed: bool = false,
    } = .{},
};

pub fn Components(comptime ComponentTypes: []const type, comptime Configs: []const ComponentConfig) type {
    if (ComponentTypes.len != ComponentTypes.len) {
        @compileError("ComponentTypes and Configs should have the same length");
    }
    return struct {
        const Hasher = TypeHasher(ComponentTypes);
        pub const ComponentConfigs = Configs;
        pub const ComponentTypeId = Hasher.TypeId;
        pub const Len = Hasher.Len;
        pub const Union = Hasher.Union;
        pub const getCanonicalType = Hasher.getCanonicalType;
        pub const getAlignment = Hasher.getAlignment;
        pub const MaxAlignment = Hasher.MaxAlignment;
        pub const getSize = Hasher.getSize;
        pub const getIndex = Hasher.getIndex;
        pub const getName = Hasher.getName;
        pub const checkSize = Hasher.checkSize;
        pub const checkType = Hasher.checkType;
        pub const getAsUnion = Hasher.getAsUnion;
        pub const isComponent = Hasher.isRegisteredType;
        pub const getAccessType = Hasher.getAccessType;
        pub const hash = Hasher.hash;
        pub const TypeIterator = Hasher.Iterator;

        const ComponentConfigMap = ComponentConfigMap: {
            @setEvalBranchQuota(ComponentTypes.len * ComponentTypes.len * 100 *
                std.math.log2_int_ceil(usize, ComponentTypes.len));
            var map = std.EnumArray(ComponentTypeId, ComponentConfig).initUndefined();
            for (ComponentTypes, 0..) |Type, i| {
                const type_id = std.meta.stringToEnum(ComponentTypeId, @typeName(Type)).?;
                map.set(type_id, ComponentConfigs[i]);
            }
            break :ComponentConfigMap map;
        };
        pub const EmptyMask = EmptyMask: {
            var sig: @This() = .{
                .bitset = BitSet.initEmpty(),
            };
            for (ComponentTypes) |Type| {
                if (@sizeOf(Type) == 0) {
                    sig.add(Type);
                }
            }
            break :EmptyMask sig;
        };
        pub const DenseStorageMask = DenseStorageMask: {
            var sig: @This() = .{
                .bitset = BitSet.initEmpty(),
            };
            for (ComponentTypes) |Type| {
                if (getConfig(Type).storage_type == .Dense) {
                    sig.add(Type);
                }
            }
            break :DenseStorageMask sig;
        };
        pub const SparseStorageMask = DenseStorageMask.complement();
        pub const AddedMetadataMask = AddedMetadataMask: {
            var sig: @This() = .{
                .bitset = BitSet.initEmpty(),
            };
            for (ComponentTypes) |Type| {
                if (getConfig(Type).track_metadata.added) {
                    sig.add(Type);
                }
            }
            break :AddedMetadataMask sig;
        };
        pub const ChangedMetadataMask = ChangedMetadataMask: {
            var sig: @This() = .{
                .bitset = BitSet.initEmpty(),
            };
            for (ComponentTypes) |Type| {
                if (getConfig(Type).track_metadata.changed) {
                    if (@sizeOf(Type) == 0) {
                        @compileError("ZST components can't have changed metadata");
                    }
                    sig.add(Type);
                }
            }
            break :ChangedMetadataMask sig;
        };
        pub const RemovedMetadataMask = RemovedMetadataMask: {
            var sig: @This() = .{
                .bitset = BitSet.initEmpty(),
            };
            for (ComponentTypes) |Type| {
                if (getConfig(Type).track_metadata.removed) {
                    sig.add(Type);
                }
            }
            break :RemovedMetadataMask sig;
        };

        pub const DenseOccupiesSpaceComponents: @This() = initFull().applyStorageTypeMask(.Dense).applyOccupiesSpaceMask();

        const BitSet = std.bit_set.StaticBitSet(ComponentTypes.len);
        /// this is where archetype signatures are stored. Comptime static maps and arrays
        /// store the info given a tid
        bitset: BitSet,

        pub fn initFull() @This() {
            return @This(){
                .bitset = BitSet.initFull(),
            };
        }
        pub fn initEmpty() @This() {
            return @This(){
                .bitset = BitSet.initEmpty(),
            };
        }
        pub fn init(comptime Types: []const type) @This() {
            const bitset = comptime bitset: {
                var set = BitSet.initEmpty();
                for (Types) |Type| {
                    const idx = Hasher.getIndex(Type);
                    set.set(idx);
                }
                break :bitset set;
            };
            return .{
                .bitset = bitset,
            };
        }

        pub fn add(self: *@This(), tid_or_component: anytype) void {
            Hasher.checkType(tid_or_component);
            self.bitset.set(Hasher.getIndex(tid_or_component));
        }

        pub fn remove(self: *@This(), tid_or_component: anytype) void {
            Hasher.checkType(tid_or_component);
            self.bitset.unset(Hasher.getIndex(tid_or_component));
        }

        /// add the set bits of two bitsets (|)
        pub fn merge(self: @This(), other: @This()) @This() {
            return @This(){ .bitset = self.bitset.unionWith(other.bitset) };
        }
        /// return a bitset with the intersection of two bitsets (&)
        pub fn intersection(self: @This(), other: @This()) @This() {
            return @This(){ .bitset = self.bitset.intersectWith(other.bitset) };
        }
        /// get bitset complement
        pub fn complement(self: @This()) @This() {
            return @This(){ .bitset = self.bitset.complement() };
        }
        /// return bits are set if they are set in the first bitset but not in the second
        pub fn difference(self: @This(), other: @This()) @This() {
            return @This(){
                .bitset = self.bitset.differenceWith(other.bitset),
            };
        }
        /// return only empty components in bitset
        pub fn applyEmptyMask(self: @This()) @This() {
            return self.intersection(comptime EmptyMask);
        }
        /// return only non empty components in bitset
        pub fn applyNonEmptyMask(self: @This()) @This() {
            return self.intersection(comptime EmptyMask.complement());
        }
        pub fn applyAddedMask(self: @This()) @This() {
            return self.intersection(comptime AddedMetadataMask);
        }
        pub fn applyChangedMask(self: @This()) @This() {
            return self.intersection(comptime ChangedMetadataMask);
        }
        pub fn applyRemovedMask(self: @This()) @This() {
            return self.intersection(comptime RemovedMetadataMask);
        }
        pub inline fn applyStorageTypeMask(self: @This(), storage_type: StorageType) @This() {
            return switch (storage_type) {
                .Dense => self.intersection(comptime DenseStorageMask),
                .Sparse => self.intersection(comptime DenseStorageMask.complement()),
            };
        }
        /// applies a mask that removes ZSTs with no Added metadata
        pub inline fn applyOccupiesSpaceMask(self: @This()) @This() {
            return self.difference(comptime EmptyMask.difference(AddedMetadataMask));
        }
        /// check if a bitset as an intersection with another
        pub fn hasIntersection(self: @This(), other: @This()) bool {
            return !self.intersection(other).eql(comptime @This().init(&.{}));
        }
        /// check if two bitsets are equal
        pub fn eql(self: @This(), other: @This()) bool {
            return self.bitset.eql(other.bitset);
        }
        /// check if bitset is empty
        pub fn empty(self: @This()) bool {
            return self.bitset.eql(BitSet.initEmpty());
        }
        /// check if bitset is superset of another
        pub fn isSupersetOf(self: @This(), other: @This()) bool {
            return self.bitset.supersetOf(other.bitset);
        }
        /// check if bitset is subset of another
        pub fn isSubsetOf(self: @This(), other: @This()) bool {
            return self.bitset.subsetOf(other.bitset);
        }

        pub fn len(self: *const @This()) usize {
            return self.bitset.count();
        }

        pub fn getType(comptime tid: ComponentTypeId) type {
            return ComponentTypes[getIndex(tid)];
        }

        pub fn format(self: *const @This(), w: *std.Io.Writer) !void {
            if (comptime Len == 0) {
                _ = try w.write(".{ }");
                return;
            }
            var iter = self.iterator();
            _ = try w.write(".{ ");
            while (iter.nextTypeId()) |tid| {
                _ = try w.write(getName(tid));
                _ = try w.write(", ");
            }
            _ = try w.write(" }");
        }

        pub fn lenNonEmpty(self: *const @This()) usize {
            var iter = self.iterator();
            var i: usize = 0;
            while (iter.nextTypeIdNonEmpty()) |_| {
                i += 1;
            }
            return i;
        }

        pub fn has(self: @This(), tid_or_component: anytype) bool {
            Hasher.checkType(tid_or_component);
            return self.bitset.isSet(Hasher.getIndex(tid_or_component));
        }

        pub inline fn getConfig(tid_or_component: anytype) ComponentConfig {
            if (comptime Len == 0) return .{};
            if (comptime @TypeOf(tid_or_component) == ComponentTypeId) {
                return ComponentConfigMap.get(tid_or_component);
            } else if (comptime isComponent(tid_or_component)) {
                return comptime ComponentConfigMap.get(Hasher.TypeIds[getIndex(tid_or_component)]);
            }
            @compileError("invalid type " ++
                @typeName(@TypeOf(tid_or_component)) ++
                ": must be a ComponentTypeId or a registered component");
        }

        pub inline fn hasAddedMetadata(tid_or_component: anytype) bool {
            return getConfig(tid_or_component).track_metadata.added;
        }

        pub inline fn hasChangedMetadata(tid_or_component: anytype) bool {
            return getConfig(tid_or_component).track_metadata.changed;
        }

        pub inline fn hasRemovedMetadata(tid_or_component: anytype) bool {
            return getConfig(tid_or_component).track_metadata.removed;
        }

        pub inline fn getStorageType(tid_or_component: anytype) StorageType {
            return getConfig(tid_or_component).storage_type;
        }

        pub fn getIndexInSet(self: @This(), tid_or_component: anytype) usize {
            const index = getIndex(tid_or_component);
            var only_left = self.bitset;
            only_left.setRangeValue(.{ .start = index, .end = ComponentTypes.len }, false);
            return only_left.count();
        }

        pub fn iterator(self: *const @This()) Iterator {
            return Iterator.init(self.bitset);
        }

        pub const Iterator = struct {
            iter: BitSet.Iterator(.{ .kind = .set, .direction = .forward }),
            pub fn init(set: BitSet) @This() {
                return .{
                    .iter = set.iterator(.{ .kind = .set, .direction = .forward }),
                };
            }
            pub fn nextTypeIdNonEmptyWithStorageType(self: *@This(), storage_type: StorageType) ?ComponentTypeId {
                if (comptime Len == 0) {
                    return null;
                }
                while (self.iter.next()) |idx| {
                    const type_id = Hasher.TypeId[idx];
                    const size = Hasher.Sizes[type_id];
                    if (size != 0 and getConfig(type_id) == storage_type) {
                        return type_id;
                    }
                }
                return null;
            }
            pub fn nextTypeIdWithStorageType(self: *@This(), storage_type: StorageType) ?ComponentTypeId {
                if (comptime Len == 0) {
                    return null;
                }
                while (self.iter.next()) |idx| {
                    const type_id = Hasher.TypeId[idx];
                    if (getConfig(type_id) == storage_type) {
                        return type_id;
                    }
                }
                return null;
            }
            pub fn nextTypeId(self: *@This()) ?ComponentTypeId {
                if (comptime Len == 0) {
                    return null;
                }
                if (self.iter.next()) |idx| {
                    return Hasher.TypeIds[idx];
                }
                return null;
            }
            pub fn nextTypeIdNonEmpty(self: *@This()) ?ComponentTypeId {
                if (comptime Len == 0) {
                    return null;
                }
                while (self.iter.next()) |idx| {
                    const size = Hasher.Sizes[idx];
                    if (size != 0) {
                        return Hasher.TypeIds[idx];
                    }
                }
                return null;
            }
            pub fn nextTypeIdZST(self: *@This()) ?ComponentTypeId {
                if (comptime Len == 0) {
                    return null;
                }
                while (self.iter.next()) |idx| {
                    const size = Hasher.Sizes[idx];
                    if (size == 0) {
                        return Hasher.TypeIds[idx];
                    }
                }
                return null;
            }
        };
    };
}

test Components {
    const typeA = u64;
    const typeB = u32;
    const typeC = struct {};
    const typeD = struct { a: u43 };
    const typeE = struct { a: u32, b: u54 };

    var signature = Components(&.{ typeA, typeB, typeC, typeD, typeE }).init(&.{ typeA, typeC, typeD, typeE });
    try std.testing.expect(signature.has(typeA));
    try std.testing.expect(!signature.has(typeB));
    try std.testing.expect(signature.has(typeC));
    try std.testing.expect(signature.has(typeD));
    try std.testing.expect(signature.has(typeE));
}
