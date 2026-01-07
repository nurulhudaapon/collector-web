const std = @import("std");

const builtin = @import("builtin");

const zx = @import("zx");
const meta = @import("zx_meta").meta;

const wasm = @import("wasm.zig");

comptime {
    if (zx.platform == .browser) {
        @export(&mainClient, .{
            .name = "mainClient",
        });

        @export(&handleEvent, .{
            .name = "handleEvent",
        });
    }
}

pub const std_options: std.Options = .{
    .log_level = .debug,
    .log_scope_levels = &.{
        .{
            .scope = .db_migrate,
            .level = .warn,
        },
        .{
            .scope = .fridge,
            .level = .warn,
        },
    },
    .logFn = if (zx.platform == .browser)
        zx.Client.logFn
    else
        std.log.defaultLog,
};

fn panicFn(msg: []const u8, _: ?usize) noreturn {
    std.log.err("panic: {s}", .{msg});
    while (true) {}
}

pub const panic = if (zx.platform == .browser)
    std.debug.FullPanic(panicFn)
else
    std.debug.simple_panic;

const config: zx.App.Config = .{
    .server = .{},
    .meta = meta,
};

pub fn main() !void {
    if (zx.platform == .browser) return;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa.deinit() == .ok) {
        std.log.err("memory leaked", .{});
    };

    const allocator = gpa.allocator();

    const app: *zx.App = try .init(allocator, config);
    defer app.deinit();

    app.info();
    try app.start();
}

var client: zx.Client = .init(
    wasm.allocator,
    .{ .components = &@import("zx_components").components },
);

fn mainClient() callconv(wasm.calling_convention) void {
    client.info();
    client.renderAll();
}

fn handleEvent(velement_id: u64, event_type_id: u8, event_id: u64) callconv(wasm.calling_convention) void {
    if (builtin.os.tag != .freestanding) return;

    const event_type: zx.Client.EventType = @enumFromInt(event_type_id);
    const handled = client.dispatchEvent(velement_id, event_type, event_id);

    if (handled) {
        client.renderAll();
    }
}
