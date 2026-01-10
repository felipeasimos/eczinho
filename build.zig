const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // library
    const lib = b.addModule("eczinho", .{
        .root_source_file = b.path("src/eczinho.zig"),
        .target = target,
        .optimize = optimize,
    });

    // library tests
    const lib_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/eczinho.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "eczinho", .module = lib },
        },
    });
    const lib_tests = b.addTest(.{
        .root_module = lib_tests_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);

    // add check step for fast ZLS diagnostics on tests and library
    const check_lib_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/eczinho.zig"),
        .target = target,
        .optimize = optimize,
    });
    const check_lib_tests = b.addTest(.{
        .root_module = check_lib_tests_mod,
    });
    const check_step = b.step("check", "Check for compile errors");
    check_step.dependOn(&check_lib_tests.step);
}
