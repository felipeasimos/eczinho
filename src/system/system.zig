const std = @import("std");

const TypeStoreFactory = @import("../resource/type_store.zig").TypeStore;
const EventStoreFactory = @import("../event/event_store.zig").EventStore;
const RemovedLogFactory = @import("../removed/removed_log.zig").RemovedComponentsLog;
const types = @import("../types.zig");
const event = @import("../event/event.zig");
const removed = @import("../removed/removed.zig");
const commands = @import("../commands/commands.zig");
const SystemData = @import("./system_data.zig").SystemData;
const ParameterData = @import("parameter_data.zig").ParameterData;
const StageLabel = @import("../scheduler/stage_label.zig").StageLabel;

pub fn isSystem(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and
        @hasDecl(T, "Marker") and
        @hasDecl(T, "Fn") and
        @TypeOf(T.Marker) == @TypeOf(System) and
        T.Marker == System;
}
pub fn isSameSystem(comptime a: type, comptime b: type) bool {
    if (comptime !isSystem(a)) {
        @compileError("type 'a' (" ++ @typeName(a) ++ ") is not a system type");
    }
    if (comptime !isSystem(b)) {
        @compileError("type 'b' (" ++ @typeName(b) ++ ") is not a system type");
    }
    return comptime @TypeOf(a.Fn) == @TypeOf(b.Fn) and a.Fn == b.Fn and a.Stage == b.Stage;
}

pub fn System(comptime function: anytype, comptime Context: type, comptime stage: StageLabel) type {
    if (@typeInfo(@TypeOf(function)) != .@"fn") {
        @compileError("a function should be provided to System(), not " ++ @typeName(@TypeOf(function)));
    }
    return struct {
        pub const Marker = System;
        pub const Fn = function;
        pub const Stage = stage;
        const Entity = Context.Entity;
        const Components = Context.Components;
        const Resources = Context.Resources;
        const Events = Context.Events;

        const World = Context.GetWorldType();
        const TypeStore = TypeStoreFactory(.{
            .TypeHasher = Resources,
        });
        const EventStore = EventStoreFactory(.{
            .Events = Events,
        });
        const RemovedLog = RemovedLogFactory(.{
            .Components = Components,
            .Entity = Entity,
        });
        const CommandsQueue = commands.CommandsQueue(.{
            .Components = Components,
            .Entity = Entity,
        });

        const FuncType = @TypeOf(Fn);
        const FuncInfo = @typeInfo(FuncType).@"fn";

        const RawReturnType: type = FuncInfo.return_type.?;
        const ReturnType: type = switch (@typeInfo(RawReturnType)) {
            .error_set, .error_union => RawReturnType,
            else => anyerror!RawReturnType,
        };
        const ArgsTuple = std.meta.ArgsTuple(FuncType);

        const NumEventReaders = numOfMarker(ParamsSlice, event.EventReader);
        const NumRemovedReaders = numOfMarker(ParamsSlice, removed.Removed);

        pub const ParamsSlice = FuncInfo.params;

        pub fn initData(alloc: std.mem.Allocator) !SystemData {
            return SystemData.init(alloc, NumEventReaders, NumRemovedReaders);
        }

        fn GetBaseType(comptime T: type) type {
            return switch (@typeInfo(T)) {
                .pointer => |p| p.child,
                .error_set, .error_union => |e| e.child,
                else => T,
            };
        }

        fn sameType(comptime T1: type, comptime T2: type) bool {
            const t1 = GetBaseType(T1);
            const t2 = GetBaseType(T2);
            if (@hasDecl(t1, "Marker") != @hasDecl(t2, "Marker")) return false;
            if (!@hasDecl(t1, "Marker")) {
                return t1 == t2;
            }
            if (@TypeOf(t1.Marker) != @TypeOf(t2.Marker)) return false;
            if (t1.Marker != t2.Marker) return false;
            return true;
        }

        fn matchMarker(comptime T: type, comptime M: anytype) bool {
            const t = GetBaseType(T);
            if (!@hasDecl(t, "Marker")) return false;
            if (@TypeOf(t.Marker) != @TypeOf(M)) return false;
            if (t.Marker != M) return false;
            return true;
        }

        fn numOfMarker(comptime ParamSlice: []const std.builtin.Type.Fn.Param, comptime M: anytype) usize {
            comptime var count = 0;
            inline for (ParamSlice) |param| {
                if (param.type) |t| {
                    if (comptime matchMarker(t, M)) {
                        count += 1;
                    }
                }
            }
            return count;
        }
        fn numOfType(comptime ParamSlice: []const std.builtin.Type.Fn.Param, comptime T: type) usize {
            comptime var count = 0;
            inline for (ParamSlice) |param| {
                if (param.type) |t| {
                    if (comptime sameType(t, T)) {
                        count += 1;
                    }
                }
            }
            return count;
        }

        const ArgDependencies = struct {
            world: *World,
            type_store: *TypeStore,
            event_store: *EventStore,
            system_data: *SystemData,
            removed_logs: *RemovedLog,
            allocator: std.mem.Allocator,
            io: std.Io,
        };
        inline fn initArg(comptime ArgType: type, deps: ArgDependencies) !ArgType {
            const InitFunc = @TypeOf(ArgType.init);
            const InitInfo = @typeInfo(InitFunc).@"fn";
            const InitArgsTuple = std.meta.ArgsTuple(InitFunc);
            const InitReturnType = InitInfo.return_type.?;
            const InitParams = InitInfo.params;

            // SAFETY: immediatly filled in the following lines
            var args: InitArgsTuple = undefined;
            inline for (InitParams, 0..) |param, i| {
                args[i] = switch (comptime param.type.?) {
                    *TypeStore => deps.type_store,
                    *World => deps.world,
                    *EventStore => deps.event_store,
                    *SystemData => deps.system_data,
                    *RemovedLog => deps.removed_logs,
                    *CommandsQueue => try deps.world.createQueue(),
                    ParameterData => ParameterData{
                        .global_index = i,
                        .type_index = numOfType(InitParams[0..i], param.type.?),
                    },
                    else => @compileError("Invalid argument type " ++
                        @typeName(param.type.?) ++
                        " for method 'init' in system requirement " ++
                        @typeName(ArgType)),
                };
            }
            return switch (@typeInfo(InitReturnType)) {
                .error_set, .error_union => try @call(.always_inline, ArgType.init, args),
                else => @call(.always_inline, ArgType.init, args),
            };
        }
        inline fn getArgs(deps: ArgDependencies) !ArgsTuple {
            // SAFETY: undefined is necessary to fill tuple with custom type
            var args: ArgsTuple = undefined;
            inline for (ParamsSlice, 0..) |param, i| {
                const ArgType = param.type.?;
                args[i] = switch (comptime ArgType) {
                    types.Tick => deps.world.getTick(),
                    *TypeStore => deps.type_store,
                    std.mem.Allocator => deps.world.allocator,
                    std.Io => deps.io,
                    else => try initArg(ArgType, deps),
                };
            }
            return args;
        }
        inline fn deinitArgs(args: anytype) void {
            inline for (ParamsSlice, 0..) |_, i| {
                args[i].deinit();
            }
        }

        pub inline fn call(deps: ArgDependencies) ReturnType {
            var args = getArgs(deps) catch @panic("Couldn't initialize system arguments");
            const result = @call(.always_inline, function, args);
            deinitArgs(&args);
            return result;
        }
    };
}
