const std = @import("std");
const archetype = @import("archetype.zig");

pub const ArchetypeStoreOptions = struct {
    Archetype: type,
    DenseStorageStore: type,
};

pub fn ArchetypeStore(options: ArchetypeStoreOptions) type {
    return struct {
        const Archetype = options.Archetype;
        const DenseStorageStore = options.DenseStorageStore;
        const DenseStorage = DenseStorageStore.DenseStorage;
        const Components = Archetype.Components;
        const Entity = Archetype.Entity;
        const Self = @This();
        archetypes: std.AutoHashMap(Components, *Archetype),
        storage_store: *DenseStorageStore,

        pub fn init(allocator: std.mem.Allocator, storage_store: *DenseStorageStore) @This() {
            return .{
                .archetypes = @FieldType(@This(), "archetypes").init(allocator),
                .storage_store = storage_store,
            };
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            var iter = self.archetypes.valueIterator();
            while (iter.next()) |arch| {
                const arch_ptr = arch.*;
                arch_ptr.deinit(allocator);
                allocator.destroy(arch_ptr);
            }
            self.archetypes.deinit();
        }
        pub fn createArchetypeSignatureList(self: *@This(), allocator: std.mem.Allocator, comptime MustHave: []const type, comptime CannotHave: []const type) !std.ArrayList(Components) {
            const must_have_components = comptime Components.init(MustHave);
            const cannot_have_components = comptime Components.init(CannotHave);

            var key_iter = self.archetypes.keyIterator();
            var arr: std.ArrayList(Components) = .empty;
            while (key_iter.next()) |key| {
                const sig = key.*;
                if (must_have_components.isSubsetOf(sig) and !cannot_have_components.hasIntersection(sig)) {
                    try arr.append(allocator, sig);
                }
            }
            return arr;
        }

        pub fn getArchetypeFromSignature(self: *@This(), signature: Components) *Archetype {
            return self.archetypes.get(signature).?;
        }
        pub fn tryGetArchetypeFromSignature(self: *@This(), allocator: std.mem.Allocator, signature: Components) !*Archetype {
            const entry = try self.archetypes.getOrPut(signature);
            if (entry.found_existing) {
                return entry.value_ptr.*;
            }

            const dense_signature = signature.applyStorageTypeMask(.Dense);
            const storage_ptr = try self.storage_store.tryGetStorageFromSignature(allocator, dense_signature);
            const arch_ptr = try allocator.create(Archetype);
            arch_ptr.* = try Archetype.init(signature, storage_ptr);
            entry.value_ptr.* = arch_ptr;
            return arch_ptr;
        }
        pub fn iterator(self: *@This()) @FieldType(@This(), "archetypes").ValueIterator {
            return self.archetypes.valueIterator();
        }
    };
}
