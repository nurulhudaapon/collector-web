const app = @import("app");

const tracked = @import("../common.zig").tracked;

pub fn GET(ctx: app.RouteCtx) !void {
    try tracked(ctx, true);
}
