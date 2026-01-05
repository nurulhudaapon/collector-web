const std = @import("std");
const Build = std.Build;
const Step = Build.Step;

const zx = @import("zx");
const ZxOptions = zx.ZxInitOptions;

fn addConfig(comptime T: type, b: *Build, options: *Step.Options, name: []const u8, default: T) void {
    const value = b.option(T, name, name) orelse default;
    options.addOption(T, name, value);
}

pub fn build(b: *Build) !void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // private modules
    const options = b.addOptions();
    addConfig(usize, b, options, "max_fetch_threads", 5);

    const api = b.createModule(.{
        .root_source_file = b.path("api/types.zig"),
        .target = target,
        .optimize = optimize,
    });

    // dependencies
    const fridge = b.dependency("fridge", .{
        // embed SQLite in binary
        .bundle = true,
    });
    const sdk = b.dependency("sdk", .{
        .target = target,
        .optimize = optimize,
    });

    // backend
    const backend = b.addModule("backend", .{
        .root_source_file = b.path("backend/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "api", .module = api },
            .{ .name = "fridge", .module = fridge.module("fridge") },
            .{ .name = "options", .module = options.createModule() },
            .{ .name = "sdk", .module = sdk.module("sdk") },
        },
    });

    // frontend
    const frontend = b.createModule(.{
        .root_source_file = b.path("frontend/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "api", .module = api },
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
            zx.plugins.tailwind(b, .{
                .bin = b.path("node_modules/.bin/tailwindcss"),
                .input = b.path("frontend/_/styles.css"),
                .output = b.path("{outdir}/public/styles.css"),
            }),
            zx.plugins.esbuild(b, .{
                .bin = b.path("node_modules/.bin/esbuild"),
                .input = b.path("frontend/main.ts"),
                .output = b.path("{outdir}/assets/main.js"),
            }),
        },
        .site = .{
            .path = b.path("frontend"),
        },
        .experimental = .{
            .enabled_csr = true,
        },
    };

    const zx_build = try zx.init(b, exe, zx_options);

    // HACK: make "api" module available to wasm executable
    if (zx_build.client_exe) |wasm| {
        if (wasm.root_module.import_table.get("zx_components")) |components| {
            components.addImport("api", api);
        }
    }

    // tests
    const tests = b.step("test", "run tests");
    const test_runner: Step.Compile.TestRunner = .{
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
