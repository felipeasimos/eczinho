const std = @import("std");

pub fn getGitHash(b: *std.Build) ![]const u8 {
    var process = std.process.Child.init(&[_][]const u8{ "git", "rev-parse", "HEAD" }, b.allocator);
    process.stdout_behavior = .Pipe;

    process.spawn() catch {
        return error.GitNotAvailable;
    };

    // Get the output
    const result: []u8 = process.stdout.?.readToEndAlloc(b.allocator, 1024) catch {
        _ = process.kill() catch @panic("Error getting git hash");
        return error.ReadFailed;
    };

    // Wait for process to finish
    const term = process.wait() catch {
        return error.WaitFailed;
    };

    // Check if process succeeded
    if (term.Exited != 0) {
        return error.GitCommandFailed;
    }

    // Trim trailing newline
    const trimmed = std.mem.trim(u8, result, "\r\n");
    if (trimmed.len != 40) {
        return error.InvalidResponse;
    }
    return trimmed;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const git_commit_hash = getGitHash(b) catch "unknown git hash";

    const options = b.addOptions();
    options.addOption([]const u8, "git_commit_hash", git_commit_hash);

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    const eczinho = b.dependency("eczinho", .{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "eczinho", .module = eczinho.module("eczinho") },
            .{ .name = "raylib", .module = raylib },
            .{ .name = "raygui", .module = raygui },
        },
    });
    exe_mod.addOptions("options", options);
    const exe = b.addExecutable(.{
        .name = "pong",
        .root_module = exe_mod,
    });

    exe.linkLibrary(raylib_artifact);

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
}
