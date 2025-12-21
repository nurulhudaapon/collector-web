const std = @import("std");

const zx = @import("zx");
const meta = @import("zx_meta").meta;

const config: zx.App.Config = .{
    .server = .{},
    .meta = meta,
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const app: *zx.App = try .init(allocator, config);
    defer app.deinit();

    app.info();
    try app.start();
}
