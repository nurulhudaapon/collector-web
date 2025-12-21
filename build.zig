const std = @import("std");

const zx_build = @import("zx");

pub fn build(b: *std.Build) !void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // dependencies
    const ptz = b.dependency("ptz", .{
        .target = target,
        .optimize = optimize,
    });
    const zmig = b.dependency("zmig", .{
        .target = target,
        .optimize = optimize,
        .migrations = b.path("migrations"),
    });
    const zx = b.dependency("zx", .{
        .target = target,
        .optimize = optimize,
    });

    // backend
    const backend = b.addModule("backend", .{
        .root_source_file = b.path("backend/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ptz", .module = ptz.module("ptz") },
            .{ .name = "zmig", .module = zmig.module("zmig") },
        },
    });

    // frontend
    const frontend = b.createModule(.{
        .root_source_file = b.path("frontend/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "backend", .module = backend },
        },
    });

    // put the server together
    const exe = b.addExecutable(.{
        .name = "collector_web",
        .root_module = frontend,
        // work around self-hosted crashing on some code
        .use_llvm = true,
    });

    const zx_options: zx_build.ZxInitOptions = .{
        .cli = .{
            .steps = .{
                .serve = "run",
                .dev = "dev",
            },
        },
        .site = .{
            .path = b.path("frontend"),
        },
    };

    try zx_build.init(b, exe, zx_options);

    // access zmig CLI
    const zmig_run = b.addRunArtifact(zmig.artifact("zmig"));
    const zmig_step = b.step("zmig", "invoke zmig's CLI");
    if (b.args) |args| zmig_run.addArgs(args);
    zmig_step.dependOn(&zmig_run.step);

    // access zx CLI
    const zx_run = b.addRunArtifact(zx.artifact("zx"));
    const zx_step = b.step("zx", "invokes zx's CLI");
    if (b.args) |args| zx_run.addArgs(args);
    zx_step.dependOn(&zx_run.step);

    // tests
    const tests = b.step("test", "run tests");
    const test_runner: std.Build.Step.Compile.TestRunner = .{
        .mode = .simple,
        .path = b.path("lib/test_runner.zig"),
    };

    const test_backend = b.addTest(.{
        .root_module = backend,
        .name = "test_backend",
        .use_llvm = true,
        .test_runner = test_runner,
    });
    tests.dependOn(&b.addRunArtifact(test_backend).step);

    const test_frontend = b.addTest(.{
        .root_module = frontend,
        .name = "test_frontend",
        .use_llvm = true,
        .test_runner = test_runner,
    });
    tests.dependOn(&b.addRunArtifact(test_frontend).step);
}
