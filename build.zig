const std = @import("std");

fn generateDocs(b: *std.Build, lib: *std.Build.Module) void {
    const docs_step = b.step("docs", "Generate documentation");
    const lib_docs = b.addObject(.{
        .name = "eczinho",
        .root_module = lib,
    });
    const install_lib_docs = b.addInstallDirectory(.{
        .source_dir = lib_docs.getEmittedDocs(),
        .install_dir = .{ .custom = "docs" },
        .install_subdir = "apidocs",
    });

    docs_step.dependOn(&install_lib_docs.step);
}

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
    // integration tests
    const integration_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "eczinho", .module = lib },
        },
    });
    const integration_tests = b.addTest(.{
        .root_module = integration_tests_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    // generate docs
    generateDocs(b, lib);

    // add check step for fast ZLS diagnostics on tests and library
    const check_lib_tests = b.addTest(.{
        .root_module = lib_tests_mod,
    });
    const check_integration_tests = b.addTest(.{
        .root_module = integration_tests_mod,
    });
    const check_step = b.step("check", "Check for compile errors");
    check_step.dependOn(&check_lib_tests.step);
    check_step.dependOn(&check_integration_tests.step);
}
