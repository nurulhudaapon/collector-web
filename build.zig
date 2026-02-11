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

    // dependencies
    const fridge = b.dependency("fridge", .{
        // embed SQLite in binary
        .bundle = true,
    });
    const graphqlz = b.dependency("graphqlz", .{ // FIXME: remove after https://github.com/tcgdex/cards-database/pull/1084
        .target = target,
        .optimize = optimize,
    });
    const sdk = b.dependency("sdk", .{
        .target = target,
        .optimize = optimize,
    });

    // private modules
    const options_builder = b.addOptions();
    addConfig(usize, b, options_builder, "max_awaitable_promises", 5);
    const options = options_builder.createModule();

    const database = b.createModule(.{
        .root_source_file = b.path("database/database.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fridge", .module = fridge.module("fridge") },
            .{ .name = "options", .module = options },
        },
    });

    // backend
    const backend = b.addModule("backend", .{
        .root_source_file = b.path("backend/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "database", .module = database },
            .{ .name = "graphqlz", .module = graphqlz.module("graphqlz") },
            .{ .name = "options", .module = options },
            .{ .name = "sdk", .module = sdk.module("sdk") },
        },
        .sanitize_thread = true,
    });

    // frontend
    const frontend = b.createModule(.{
        .root_source_file = b.path("frontend/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "backend", .module = backend },
            .{ .name = "database", .module = database },
        },
    });
    frontend.addImport("app", frontend);

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
        .app = .{
            .path = b.path("frontend"),
        },
    };

    const zx_build = try zx.init(b, exe, zx_options);

    // HACK: make module available to ZX modules
    for (&[_]*Build.Step.Compile{ zx_build.zx_exe, zx_build.client_exe orelse @panic("no client exe") }) |executable| {
        const module = executable.root_module.import_table.get("zx") orelse continue;

        if (module.import_table.get("zx_meta")) |meta| {
            meta.addImport("options", options);
        }
    }

    // steps
    const test_step = b.step("test", "run tests");
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
    test_step.dependOn(&b.addRunArtifact(test_backend).step);

    const test_frontend = b.addTest(.{
        .root_module = frontend,
        .name = "test_frontend",
        .use_llvm = true,
        .test_runner = test_runner,
    });
    test_step.dependOn(&b.addRunArtifact(test_frontend).step);
}
