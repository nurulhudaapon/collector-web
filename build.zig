const std = @import("std");

const zx_build = @import("zx");
const ZxOptions = zx_build.ZxInitOptions;

pub fn build(b: *std.Build) !void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // dependencies
    const fridge = b.dependency("fridge", .{
        // embed SQLite in binary
        .bundle = true,
    });
    const ptz = b.dependency("ptz", .{
        .target = target,
        .optimize = optimize,
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
            .{ .name = "fridge", .module = fridge.module("fridge") },
            .{ .name = "ptz", .module = ptz.module("ptz") },
            .{ .name = "zx", .module = zx.module("zx") },
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
        .name = "collector-web",
        .root_module = frontend,
        // work around self-hosted crashing on some code
        .use_llvm = true,
    });

    const zx_options: ZxOptions = .{
        .cli = .{
            .steps = .{
                .serve = "run",
                .dev = "dev",
            },
        },
        .plugins = &.{
            zx_build.plugins.tailwind(b, .{
                .bin = b.path("node_modules/.bin/tailwindcss"),
                .input = b.path("frontend/_/styles.css"),
                .output = b.path("{outdir}/public/styles.css"),
            }),
        },
        .site = .{
            .path = b.path("frontend"),
        },
    };

    _ = try zx_build.init(b, exe, zx_options);

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
