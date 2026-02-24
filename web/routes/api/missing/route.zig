const app = @import("app");

const owned = @import("../common.zig").owned;

pub fn GET(ctx: app.RouteCtx) !void {
    try owned(ctx, false);
}
