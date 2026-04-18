const Tick = @import("../types.zig").Tick;

pub const MutOptions = struct {
    T: type,
    Components: type,
    Storage: type,
};

/// returned instead of the raw mutable pointer, so changes can be marked
/// (if component has metadata)
pub fn Mut(comptime options: MutOptions) type {
    return struct {
        pub const T = options.T;
        pub const Marker = Mut;
        const Components = options.Components;
        const Storage = options.Storage;
        const StorageAddress = Storage.StorageAddress;
        const Data = if (Components.hasChangedMetadata(T)) struct {
            storage_address: StorageAddress,
            current_run: Tick,
        } else struct {
            storage_address: StorageAddress,
        };
        data: Data,
        pub inline fn init(storage_address: StorageAddress, current_run: Tick) @This() {
            if (comptime Components.hasChangedMetadata(T)) {
                return .{
                    .data = .{
                        .storage_address = storage_address,
                        .current_run = current_run,
                    },
                };
            }
            return .{
                .data = .{
                    .storage_address = storage_address,
                },
            };
        }
        inline fn getRefMut(self: @This()) *T {
            const storage, const index = self.data.storage_address;
            if (comptime Components.hasChangedMetadata(T)) {
                storage.getChanged(T, index).* = self.data.current_run;
            }
            return storage.get(T, index);
        }
        inline fn getRefConst(self: @This()) *const T {
            const storage, const index = self.data.storage_address;
            return @ptrCast(storage.get(T, index));
        }
        pub inline fn getPtrConst(self: @This()) *const T {
            return self.getRefConst();
        }
        pub inline fn get(self: @This()) *T {
            return self.getRefMut();
        }
        pub inline fn set(self: @This(), v: anytype) void {
            if (comptime @TypeOf(v) == *T or @TypeOf(v) == *const T) {
                self.getRefMut().* = v.*;
            }
            self.getRefMut().* = v;
        }
        pub inline fn clone(self: @This()) T {
            return self.getRefConst().*;
        }
    };
}
