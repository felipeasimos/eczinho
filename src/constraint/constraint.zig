const StageLabel = @import("../scheduler/stage_label.zig").StageLabel;
const system = @import("../system/system.zig");

pub const SystemConstraint = union(enum) {
    num_threads: usize,
    comes_after: type,
    use_main_thread: void,
};

pub const StageConstraint = union(enum) {
    max_num_threads: usize,
};

pub const Constraint = union(enum) {
    pub fn Builder(comptime Context: type) type {
        return struct {
            /// will use only main thread without multithreading overhead if set to 1
            pub fn stageNumThreads(comptime stage: StageLabel, comptime n: usize) Constraint {
                return .{ .stage = .{
                    .stage = stage,
                    .constraint = .{ .max_num_threads = n },
                } };
            }
            pub fn systemNumThreads(comptime stage: StageLabel, comptime function: anytype, comptime n: usize) Constraint {
                return .{ .system = .{
                    .system = system.System(function, Context, stage),
                    .constraint = .{ .max_num_threads = n },
                } };
            }
            /// calling systemNumThreads to set the number of threads to 1 is redudant
            pub fn systemUseMainThread(comptime stage: StageLabel, comptime function: anytype) Constraint {
                return .{ .system = .{
                    .system = system.System(function, Context, stage),
                    .constraint = .use_main_thread,
                } };
            }
            pub fn after(comptime stage: StageLabel, comptime functionA: anytype, comptime functionB: anytype) Constraint {
                return .{ .system = .{
                    .system = system.System(functionA, Context, stage),
                    .constraint = .{ .comes_after = system.System(functionB, Context, stage) },
                } };
            }
        };
    }

    system: struct {
        system: type,
        constraint: SystemConstraint,
    },
    stage: struct {
        stage: StageLabel,
        constraint: StageConstraint,
    },

    pub fn getStageNumThreads(comptime constraints: []const @This(), comptime stage: StageLabel) usize {
        inline for (constraints) |constraint| {
            switch (constraint) {
                .stage => |st| if (st.stage == stage) {
                    switch (st.constraint) {
                        .max_num_threads => |n| return n,
                    }
                },
                else => {},
            }
        }
        return 4;
    }
    pub fn getSystemUseMainThread(comptime constraints: []const @This(), comptime sys: type) bool {
        inline for (constraints) |constraint| {
            switch (constraint) {
                .system => |s| if (system.isSameSystem(sys, s.system)) {
                    switch (s.constraint) {
                        .use_main_thread => return true,
                        else => {},
                    }
                },
                else => {},
            }
        }
        return false;
    }
};
