const std = @import("std");

const RegistryFactory = @import("registry.zig").Registry;
const TypeStoreFactory = @import("resource/type_store.zig").TypeStore;
const EventStoreFactory = @import("event/event_store.zig").EventStore;
const event = @import("event/event.zig");
const SystemData = @import("system_data.zig").SystemData;

pub fn System(comptime function: anytype, comptime Context: type) type {
    return struct {
        pub const Entity = Context.Entity;
        pub const Components = Context.Components;
        pub const Resources = Context.Resources;
        pub const Events = Context.Events;

        pub const Registry = RegistryFactory(.{
            .Components = Components,
            .Entity = Entity,
        });
        pub const TypeStore = TypeStoreFactory(.{
            .Resources = Resources,
        });
        pub const EventStore = EventStoreFactory(.{
            .Events = Events,
        });

        pub const FuncType = @TypeOf(function);
        pub const FuncInfo = @typeInfo(FuncType).@"fn";

        pub const RawReturnType = FuncInfo.return_type.?;
        pub const ReturnType = switch (@typeInfo(RawReturnType)) {
            .error_set, .error_union => RawReturnType,
            else => !RawReturnType,
        };
        pub const ParamsSlice = FuncInfo.params;
        pub const ArgsTuple = std.meta.ArgsTuple(FuncType);

        pub const NumEventReaders = NumEventReaders: {
            var i = 0;
            for (ParamsSlice) |param| {
                if (param.type) |t| {
                    if (!@hasField(t, "Marker")) {
                        continue;
                    }
                    if (t.Marker != event.EventReader) {
                        continue;
                    }
                    i += 1;
                }
            }
            break :NumEventReaders i;
        };

        pub fn initData(alloc: std.mem.Allocator) !SystemData {
            return SystemData.init(alloc, NumEventReaders);
        }

        const Dependencies = struct {
            registry: *Registry,
            type_store: *TypeStore,
            event_store: *EventStore,
            system_data: *SystemData,
        };
        inline fn initArg(comptime ArgType: type, deps: Dependencies) !ArgType {
            const InitFunc = @TypeOf(ArgType.init);
            const InitInfo = @typeInfo(InitFunc).@"fn";
            const InitArgsTuple = std.meta.ArgsTuple(InitFunc);
            const InitReturnType = InitInfo.return_type.?;
            const InitParams = InitInfo.params;

            var args: InitArgsTuple = undefined;
            inline for (InitParams, 0..) |param, i| {
                args[i] = switch (comptime param.type.?) {
                    *TypeStore => deps.type_store,
                    *Registry => deps.registry,
                    *EventStore => deps.event_store,
                    *SystemData => deps.system_data,
                    else => @compileError(std.fmt.comptimePrint("Invalid argument type {s} for method 'init' in system requirement {s}", .{ @typeName(param.type.?), @typeName(ArgType) })),
                };
            }
            return switch (@typeInfo(InitReturnType)) {
                .error_set, .error_union => try @call(.always_inline, ArgType.init, args),
                else => @call(.always_inline, ArgType.init, args),
            };
        }
        inline fn getArgs(deps: Dependencies) !ArgsTuple {
            var args: ArgsTuple = undefined;
            inline for (ParamsSlice, 0..) |param, i| {
                const ArgType = param.type.?;
                args[i] = try initArg(ArgType, deps);
            }
            return args;
        }
        inline fn deinitArgs(args: anytype) void {
            inline for (ParamsSlice, 0..) |_, i| {
                args[i].deinit();
            }
        }

        pub inline fn call(deps: Dependencies) ReturnType {
            var args = getArgs(deps) catch @panic("Couldn't initialize system arguments");
            const result = switch (@typeInfo(ReturnType)) {
                .error_set, .error_union => try @call(.always_inline, function, args),
                else => @call(.auto, function, args),
            };
            deinitArgs(&args);
            return result;
        }
    };
}
