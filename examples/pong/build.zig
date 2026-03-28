const std = @import("std");

pub fn getGitHash(b: *std.Build) ![]const u8 {
    const result = try std.process.run(b.allocator, b.graph.io, .{ .argv = &[_][]const u8{ "git", "rev-parse", "HEAD" } });

    // Trim trailing newline
    const trimmed = std.mem.trim(u8, result.stdout, "\r\n");
    if (trimmed.len != 40) {
        return error.InvalidResponse;
    }
    return trimmed;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tracy_enabled = b.option(
        bool,
        "tracy",
        "Build with Tracy support.",
    ) orelse false;
    const git_commit_hash = getGitHash(b) catch "unknown git hash";

    const options = b.addOptions();
    options.addOption([]const u8, "git_commit_hash", git_commit_hash);

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linkage = .static,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    const eczinho = b.dependency("eczinho", .{});
    const tracy = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "eczinho", .module = eczinho.module("eczinho") },
            .{ .name = "raylib", .module = raylib },
            .{ .name = "raygui", .module = raygui },
            .{ .name = "tracy", .module = tracy.module("tracy") },
        },
    });
    exe_mod.addOptions("options", options);
    exe_mod.linkLibrary(raylib_artifact);

    // Pick an implementation based on the build flags.
    // Don't build both, we don't want to link with Tracy at all unless we intend to enable it.
    if (tracy_enabled) {
        // The user asked to enable Tracy, use the real implementation
        exe_mod.addImport("tracy_impl", tracy.module("tracy_impl_enabled"));
    } else {
        // The user asked to disable Tracy, use the dummy implementation
        exe_mod.addImport("tracy_impl", tracy.module("tracy_impl_disabled"));
    }
    const exe = b.addExecutable(.{
        .name = "pong",
        .root_module = exe_mod,
        .use_llvm = true,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    const check_exe = b.addExecutable(.{
        .name = "check",
        .root_module = exe_mod,
    });

    const check_step = b.step("check", "Check for compile errors");
    check_step.dependOn(&check_exe.step);
}
