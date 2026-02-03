const std = @import("std");
const assert = std.debug.assert;

const builtin = @import("builtin");

const zx = @import("zx");

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

const AppContext = struct {};

pub const std_options: std.Options = .{
    .log_level = .debug,
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
    .server = .{
        .port = 3000,
    },
};

pub fn main() !void {
    if (zx.platform == .browser) return;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    const server: *zx.Server(AppContext) = try .init(allocator, config, .{});
    defer server.deinit();

    server.info();
    try server.start();
}

var client: zx.Client = .init(wasm.allocator, .{});

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
