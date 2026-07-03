const StageLabel = @import("../scheduler/stage_label.zig").StageLabel;
const defaults = @import("../defaults.zig");
const System = @import("../system/system.zig");

pub const SystemConstraint = union(enum) {
    num_threads: usize,
    comes_after: type,
    comes_directly_after: type,
};

pub const StageConstraint = union(enum) {
    max_num_threads: usize,
};

pub const Constraint = union(enum) {
    pub fn Builder(comptime Context: type) type {
        return struct {
            pub fn stageNumThreads(comptime stage: StageLabel, comptime n: usize) Constraint {
                return .{ .stage = .{
                    .stage = stage,
                    .constraint = .{ .max_num_threads = n },
                } };
            }
            pub fn systemNumThreads(comptime stage: StageLabel, comptime function: anytype, comptime n: usize) Constraint {
                return .{ .system = .{
                    .system = System(function, Context, stage),
                    .constraint = .{ .max_num_threads = n },
                } };
            }
            pub fn after(comptime stage: StageLabel, comptime functionA: anytype, comptime functionB: anytype) Constraint {
                return .{ .system = .{
                    .system = System(functionA, Context, stage),
                    .constraint = .{ .comes_after = System(functionB, Context, stage) },
                } };
            }
            pub fn directlyAfter(
                comptime stage: StageLabel,
                comptime functionA: anytype,
                comptime functionB: anytype,
            ) Constraint {
                return .{ .system = .{
                    .system = System(functionA, Context, stage),
                    .constraint = .{ .comes_directly_after = System(functionB, Context, stage) },
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
                .system => {},
            }
        }
        return defaults.NUM_THREADS;
    }
};
